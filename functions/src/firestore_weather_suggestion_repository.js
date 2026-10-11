const { WeatherPipelineError, validateWeatherRule, validateWeatherSource } = require('./weather_suggestion_service');
const { approvedTemplateFromRecord, templateDocumentId } = require('./task_campaign_service');

const OPERATOR_ROLES = new Set(['KETUA_RT_RW', 'PENDAMPING_RT']);
const RT_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/u;
const RULE_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/u;
const HASH_ID_PATTERN = /^[a-f0-9]{40}$/u;
const WEATHER_SOURCE_COLLECTION = 'weather_sources';
const WEATHER_RULE_COLLECTION = 'weather_rules';
const WEATHER_SNAPSHOT_COLLECTION = 'weather_snapshots';
const LAST_VALID_COLLECTION = 'weather_last_valid_snapshots';
const SUGGESTION_COLLECTION = 'task_suggestions';

function denyOperator() {
  return new WeatherPipelineError('permission-denied', 'Akses operator tidak valid.');
}

function invalidData() {
  return new WeatherPipelineError('failed-precondition', 'Data cuaca tidak konsisten.');
}

function asDate(value) {
  let date;
  if (value instanceof Date) date = value;
  else if (value && typeof value.toDate === 'function') {
    try { date = value.toDate(); } catch (_) { return null; }
  } else return null;
  return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
}

function requireOperator(snapshot) {
  const operator = snapshot.data();
  if (!snapshot.exists || operator?.active !== true || !OPERATOR_ROLES.has(operator.role) ||
      typeof operator.rtId !== 'string' || !RT_ID_PATTERN.test(operator.rtId)) {
    throw denyOperator();
  }
  return operator.rtId;
}

function latestWeatherRuleRecords(snapshots, rtId) {
  const latestByRule = new Map();
  for (const snapshot of snapshots) {
    const record = snapshot.data();
    if (record?.rtId !== rtId || !RULE_ID_PATTERN.test(record.ruleId || '') ||
        !Number.isInteger(record.version) || record.version < 1 ||
        snapshot.id !== `${rtId}_${record.ruleId}_v${record.version}`) continue;
    const current = latestByRule.get(record.ruleId);
    if (!current || record.version > current.record.version) {
      latestByRule.set(record.ruleId, { record, snapshot });
    }
  }
  return [...latestByRule.values()];
}

function snapshotRecord(record, expectedId, expectedRtId) {
  const sourceUpdatedAt = asDate(record?.sourceUpdatedAt);
  const fetchedAt = asDate(record?.fetchedAt);
  if (!record || record.snapshotId !== expectedId || record.rtId !== expectedRtId ||
      record.source !== 'BMKG' || !sourceUpdatedAt || !fetchedAt ||
      !/^[a-f0-9]{64}$/u.test(record.sourceFingerprint || '') ||
      !Number.isFinite(record.rainfallMm) || record.rainfallMm < 0 ||
      typeof record.isLastValid !== 'boolean') throw invalidData();
  return {
    id: record.snapshotId,
    rtId: record.rtId,
    source: 'BMKG',
    sourceFingerprint: record.sourceFingerprint,
    sourceUpdatedAt,
    fetchedAt,
    rainfallMm: record.rainfallMm,
  };
}

function sameSnapshot(left, right) {
  return left.rtId === right.rtId && left.source === right.source &&
    left.sourceFingerprint === right.sourceFingerprint &&
    left.sourceUpdatedAt.getTime() === right.sourceUpdatedAt.getTime() &&
    left.rainfallMm === right.rainfallMm;
}

function suggestionFingerprint(record) {
  return JSON.stringify([
    record.suggestionId,
    record.rtId,
    record.source,
    record.snapshotId,
    record.sourceFingerprint,
    record.sourceUpdatedAt.toISOString(),
    record.fetchedAt.toISOString(),
    record.rainfallMm,
    record.maximumAgeSeconds,
    record.ruleId,
    record.ruleVersion,
    record.ruleFingerprint,
    record.recommendedTemplateVersions,
    record.explanation,
    record.state,
  ]);
}

function validateSuggestion(record, expectedId, expectedRtId) {
  const sourceUpdatedAt = asDate(record?.sourceUpdatedAt);
  const fetchedAt = asDate(record?.fetchedAt);
  const createdAt = asDate(record?.createdAt);
  if (!record || record.suggestionId !== expectedId || record.rtId !== expectedRtId ||
      record.source !== 'BMKG' || !HASH_ID_PATTERN.test(record.snapshotId || '') ||
      !/^[a-f0-9]{64}$/u.test(record.sourceFingerprint || '') ||
      !/^[a-z][a-z0-9_-]{0,63}$/u.test(record.ruleId || '') ||
      !Number.isInteger(record.ruleVersion) || record.ruleVersion < 1 ||
      !/^[a-f0-9]{64}$/u.test(record.ruleFingerprint || '') ||
      record.state !== 'SUGGESTED' || !sourceUpdatedAt || !fetchedAt || !createdAt ||
      !Number.isFinite(record.rainfallMm) || record.rainfallMm < 0 ||
      !Number.isInteger(record.maximumAgeSeconds) || record.maximumAgeSeconds < 1 ||
      !Array.isArray(record.recommendedTemplateVersions) ||
      record.recommendedTemplateVersions.length < 1 ||
      record.recommendedTemplateVersions.length > 10 ||
      typeof record.explanation !== 'string' || record.explanation.trim().length === 0 ||
      record.explanation.length > 240) throw invalidData();
  const normalized = {
    ...record,
    sourceUpdatedAt,
    fetchedAt,
    createdAt,
  };
  const fingerprint = suggestionFingerprint(normalized);
  if (record.suggestionFingerprint !== undefined && record.suggestionFingerprint !== fingerprint) {
    throw invalidData();
  }
  return { ...normalized, suggestionFingerprint: fingerprint };
}

class FirestoreWeatherSuggestionRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async listEnabledWeatherSources() {
    const result = await this.firestore.collection(WEATHER_SOURCE_COLLECTION)
      .where('enabled', '==', true)
      .get();
    return result.docs.map((snapshot) => ({
      ...snapshot.data(),
      sourceId: snapshot.id,
    }));
  }

  async saveSnapshotIfNewer(candidate) {
    if (!candidate || !HASH_ID_PATTERN.test(candidate.id || '') ||
        !RT_ID_PATTERN.test(candidate.rtId || '') || candidate.source !== 'BMKG' ||
        !/^[a-f0-9]{64}$/u.test(candidate.sourceFingerprint || '') ||
        !asDate(candidate.sourceUpdatedAt) || !asDate(candidate.fetchedAt) ||
        !Number.isFinite(candidate.rainfallMm) || candidate.rainfallMm < 0) {
      throw invalidData();
    }
    const snapshots = this.firestore.collection(WEATHER_SNAPSHOT_COLLECTION);
    const snapshotRef = snapshots.doc(candidate.id);
    const lastRef = this.firestore.collection(LAST_VALID_COLLECTION).doc(candidate.rtId);
    let result;
    await this.firestore.runTransaction(async (transaction) => {
      const [lastSnapshot, candidateSnapshot] = await Promise.all([
        transaction.get(lastRef),
        transaction.get(snapshotRef),
      ]);
      let previousSnapshot = null;
      let previousRef = null;
      let previousData = null;
      if (lastSnapshot.exists) {
        previousData = lastSnapshot.data();
        if (previousData?.rtId !== candidate.rtId ||
            !HASH_ID_PATTERN.test(previousData?.snapshotId || '')) throw invalidData();
        previousRef = snapshots.doc(previousData.snapshotId);
        if (previousData.snapshotId === candidate.id) {
          previousSnapshot = candidateSnapshot;
        } else {
          previousSnapshot = await transaction.get(previousRef);
        }
        if (!previousSnapshot.exists || previousSnapshot.data()?.isLastValid !== true) {
          throw invalidData();
        }
      }

      const storedCandidate = candidateSnapshot.exists
        ? snapshotRecord(candidateSnapshot.data(), candidate.id, candidate.rtId)
        : null;
      if (storedCandidate && !sameSnapshot(storedCandidate, candidate)) throw invalidData();
      if (previousData && previousData.snapshotId === candidate.id) {
        result = { snapshot: snapshotRecord(candidateSnapshot.data(), candidate.id, candidate.rtId), updated: false };
        return;
      }
      if (previousData) {
        const previous = snapshotRecord(previousSnapshot.data(), previousData.snapshotId, candidate.rtId);
        if (previous.sourceUpdatedAt > candidate.sourceUpdatedAt ||
            (previous.sourceUpdatedAt.getTime() === candidate.sourceUpdatedAt.getTime() &&
              (previous.sourceFingerprint === candidate.sourceFingerprint ||
                candidate.fetchedAt <= previous.fetchedAt))) {
          result = { snapshot: previous, updated: false };
          return;
        }
      }

      const nextRecord = {
        snapshotId: candidate.id,
        rtId: candidate.rtId,
        source: 'BMKG',
        sourceFingerprint: candidate.sourceFingerprint,
        sourceUpdatedAt: candidate.sourceUpdatedAt,
        fetchedAt: candidate.fetchedAt,
        rainfallMm: candidate.rainfallMm,
        isLastValid: true,
      };
      if (storedCandidate) transaction.update(snapshotRef, { isLastValid: true });
      else transaction.create(snapshotRef, nextRecord);
      if (previousData && previousRef) transaction.update(previousRef, { isLastValid: false });
      transaction.set(lastRef, {
        rtId: candidate.rtId,
        snapshotId: candidate.id,
        sourceFingerprint: candidate.sourceFingerprint,
        sourceUpdatedAt: candidate.sourceUpdatedAt,
        fetchedAt: candidate.fetchedAt,
      });
      result = { snapshot: candidate, updated: true };
    });
    return result;
  }

  async listReviewedWeatherRules(rtId) {
    if (!RT_ID_PATTERN.test(rtId || '')) return [];
    const query = await this.firestore.collection(WEATHER_RULE_COLLECTION)
      .where('rtId', '==', rtId)
      .get();
    const now = new Date();
    const candidates = [];
    for (const { record, snapshot } of latestWeatherRuleRecords(query.docs, rtId)) {
      try {
        const rule = validateWeatherRule(record, rtId, now);
        candidates.push({ record, rule, snapshot });
      } catch (_) {
        // A malformed, unreviewed, or disabled newest version supersedes older rules.
      }
    }
    const templateIds = [...new Set(candidates.flatMap(({ rule }) =>
      rule.suggestedTemplateVersions.map(({ templateId, version }) =>
        templateDocumentId(templateId, version))))];
    const templateSnapshots = templateIds.length === 0
      ? []
      : await this.firestore.getAll(...templateIds.map((id) =>
        this.firestore.collection('task_templates').doc(id)));
    const templates = new Map(templateSnapshots.map((snapshot) => [snapshot.id, snapshot]));
    const result = [];
    for (const { record, rule } of candidates) {
      let valid = true;
      for (const reference of rule.suggestedTemplateVersions) {
        const documentId = templateDocumentId(reference.templateId, reference.version);
        const snapshot = templates.get(documentId);
        const template = snapshot?.exists === true
          ? approvedTemplateFromRecord(snapshot.data(), reference.templateId, reference.version)
          : null;
        if (!template || template.fingerprint !== reference.fingerprint) {
          valid = false;
          break;
        }
      }
      if (valid) result.push(record);
    }
    return result;
  }

  async createSuggestionsIfMissing(suggestions) {
    let created = 0;
    for (const suggestion of suggestions) {
      const record = validateSuggestion(suggestion, suggestion.suggestionId, suggestion.rtId);
      const suggestionRef = this.firestore.collection(SUGGESTION_COLLECTION).doc(record.suggestionId);
      const inserted = await this.firestore.runTransaction(async (transaction) => {
        const existing = await transaction.get(suggestionRef);
        if (existing.exists) {
          const stored = validateSuggestion(
            { ...existing.data(), suggestionFingerprint: existing.data().suggestionFingerprint },
            suggestionRef.id,
            record.rtId,
          );
          if (stored.suggestionFingerprint !== record.suggestionFingerprint) throw invalidData();
          return false;
        }
        transaction.create(suggestionRef, record);
        return true;
      });
      if (inserted) created += 1;
    }
    return created;
  }

  async listSuggestionsForOperator(operatorUid, { limit = 50 } = {}) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw invalidData();
    const operatorRef = this.firestore.collection('operators').doc(operatorUid);
    let result;
    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const rtId = requireOperator(operatorSnapshot);
      const suggestionQuery = this.firestore.collection(SUGGESTION_COLLECTION)
        .where('rtId', '==', rtId)
        .where('state', '==', 'SUGGESTED')
        .orderBy('createdAt', 'desc')
        .limit(limit);
      const ruleQuery = this.firestore.collection(WEATHER_RULE_COLLECTION)
        .where('rtId', '==', rtId);
      const sourceRef = this.firestore.collection(WEATHER_SOURCE_COLLECTION).doc(rtId);
      const [suggestions, ruleSnapshots, sourceSnapshot] = await Promise.all([
        transaction.get(suggestionQuery),
        transaction.get(ruleQuery),
        transaction.get(sourceRef),
      ]);
      const now = new Date();
      let sourceConfig = null;
      try {
        if (sourceSnapshot.exists) {
          sourceConfig = validateWeatherSource({
            ...sourceSnapshot.data(),
            sourceId: sourceSnapshot.id,
          }, now);
        }
      } catch (_) {
        // Unconfigured, disabled, or changed source config hides old suggestions.
      }
      const latestRules = new Map();
      for (const { record } of latestWeatherRuleRecords(ruleSnapshots.docs, rtId)) {
        try {
          const rule = validateWeatherRule(record, rtId, now);
          latestRules.set(rule.ruleId, { record, rule });
        } catch (_) {
          // A malformed, unreviewed, or disabled newest version hides older suggestions.
        }
      }
      const templateIds = [...new Set([...latestRules.values()].flatMap(({ rule }) =>
        rule.suggestedTemplateVersions.map(({ templateId, version }) =>
          templateDocumentId(templateId, version))))];
      const templateRefs = templateIds.map((id) => this.firestore.collection('task_templates').doc(id));
      const templateSnapshots = await Promise.all(templateRefs.map((reference) =>
        transaction.get(reference)));
      const templates = new Map(templateSnapshots.map((snapshot) => [snapshot.id, snapshot]));
      const currentRules = new Map();
      for (const [ruleId, { rule }] of latestRules) {
        let valid = true;
        for (const reference of rule.suggestedTemplateVersions) {
          const documentId = templateDocumentId(reference.templateId, reference.version);
          const snapshot = templates.get(documentId);
          const template = snapshot?.exists === true
            ? approvedTemplateFromRecord(snapshot.data(), reference.templateId, reference.version)
            : null;
          if (!template || template.fingerprint !== reference.fingerprint) {
            valid = false;
            break;
          }
        }
        if (valid) currentRules.set(ruleId, rule);
      }
      result = sourceConfig ? suggestions.docs.map((snapshot) =>
        validateSuggestion(snapshot.data(), snapshot.id, rtId)).filter((suggestion) => {
        const current = currentRules.get(suggestion.ruleId);
        return suggestion.sourceFingerprint === sourceConfig.sourceFingerprint &&
          current?.version === suggestion.ruleVersion &&
          current.ruleFingerprint === suggestion.ruleFingerprint;
      }) : [];
    });
    return result;
  }
}

module.exports = { FirestoreWeatherSuggestionRepository };
