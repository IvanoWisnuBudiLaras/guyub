const crypto = require('node:crypto');
const RT_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/u;
const RULE_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/u;
const TEMPLATE_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/u;
const MAX_WEATHER_AGE_SECONDS = 7 * 24 * 60 * 60;
const MAX_RECOMMENDED_TEMPLATES = 10;
const MAX_SUGGESTION_PAGE_SIZE = 50;

class WeatherPipelineError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'WeatherPipelineError';
    this.code = code;
  }
}

function invalidWeather(message = 'Konfigurasi cuaca tidak valid.') {
  return new WeatherPipelineError('failed-precondition', message);
}

function invalidArgument(message = 'Permintaan saran cuaca tidak valid.') {
  return new WeatherPipelineError('invalid-argument', message);
}

function permissionDenied() {
  return new WeatherPipelineError('permission-denied', 'Akses operator tidak valid.');
}

function asDate(value) {
  let date;
  if (value instanceof Date) date = value;
  else if (value && typeof value.toDate === 'function') {
    try { date = value.toDate(); } catch (_) { return null; }
  } else return null;
  return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function exactKeys(value, keys) {
  return value != null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === keys.length &&
    keys.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

function validReview(record, now) {
  const reviewedAt = asDate(record.reviewedAt);
  return record.reviewStatus === 'approved' &&
    typeof record.reviewedBy === 'string' && record.reviewedBy.trim().length > 0 &&
    record.reviewedBy.trim().length <= 128 && reviewedAt !== null &&
    reviewedAt.getTime() <= now.getTime();
}

function validJsonPath(path) {
  return Array.isArray(path) && path.length > 0 && path.length <= 16 &&
    path.every((part) => Number.isInteger(part)
      ? part >= 0 && part <= 1000
      : typeof part === 'string' && /^[A-Za-z0-9_-]{1,64}$/u.test(part));
}

function validateBmkgEndpoint(value) {
  if (typeof value !== 'string' || value.length > 2048 || /[\u0000-\u0020\u007F]/u.test(value)) {
    throw invalidWeather();
  }
  let url;
  try { url = new URL(value); } catch (_) { throw invalidWeather(); }
  const administrativeCode = url.searchParams.get('adm4');
  if (url.protocol !== 'https:' || url.hostname !== 'api.bmkg.go.id' ||
      url.username || url.password || (url.port && url.port !== '443') ||
      url.pathname !== '/publik/prakiraan-cuaca' || url.hash ||
      url.searchParams.size !== 1 ||
      typeof administrativeCode !== 'string' ||
      !/^\d{2}\.\d{2}\.\d{2}\.\d{4}$/u.test(administrativeCode)) {
    throw invalidWeather();
  }
  return url.toString();
}

function validateWeatherSource(record, now) {
  const sourceId = record?.sourceId;
  const sourceFingerprint = record?.sourceFingerprint;
  const configuration = record == null ? record : Object.fromEntries(
    Object.entries(record).filter(([key]) => key !== 'sourceId' && key !== 'sourceFingerprint'),
  );
  const expected = [
    'rtId', 'source', 'enabled', 'reviewStatus', 'reviewedBy', 'reviewedAt',
    'endpoint', 'maximumAgeSeconds', 'normalization',
  ];
  if (!exactKeys(configuration, expected) ||
      (sourceId !== undefined && sourceId !== configuration.rtId) ||
      !RT_ID_PATTERN.test(configuration.rtId || '') || configuration.enabled !== true ||
      configuration.source !== 'BMKG' || !validReview(configuration, now) ||
      !Number.isInteger(configuration.maximumAgeSeconds) ||
      configuration.maximumAgeSeconds < 60 ||
      configuration.maximumAgeSeconds > MAX_WEATHER_AGE_SECONDS ||
      !exactKeys(configuration.normalization, ['rainfallMmPath', 'sourceUpdatedAtPath']) ||
      !validJsonPath(configuration.normalization.rainfallMmPath) ||
      !validJsonPath(configuration.normalization.sourceUpdatedAtPath)) {
    throw invalidWeather();
  }
  const validated = {
    ...configuration,
    endpoint: validateBmkgEndpoint(configuration.endpoint),
    normalization: {
      rainfallMmPath: [...configuration.normalization.rainfallMmPath],
      sourceUpdatedAtPath: [...configuration.normalization.sourceUpdatedAtPath],
    },
  };
  const computedFingerprint = sha256(JSON.stringify([
    validated.rtId,
    validated.endpoint,
    validated.maximumAgeSeconds,
    validated.normalization.rainfallMmPath,
    validated.normalization.sourceUpdatedAtPath,
  ]));
  if (sourceFingerprint !== undefined && sourceFingerprint !== computedFingerprint) {
    throw invalidWeather();
  }
  return { ...validated, sourceFingerprint: computedFingerprint };
}

function readJsonPath(payload, path) {
  let value = payload;
  for (const part of path) {
    if (value == null || typeof value !== 'object' || !Object.hasOwn(value, part)) return undefined;
    value = value[part];
  }
  return value;
}

function parseRainfall(value) {
  const parsed = typeof value === 'number' ? value
    : typeof value === 'string' && value.trim().length > 0 ? Number(value.trim()) : NaN;
  if (!Number.isFinite(parsed) || parsed < 0) throw invalidWeather('Data prakiraan BMKG tidak valid.');
  return parsed;
}

function parseSourceUpdatedAt(value) {
  if (typeof value !== 'string' || !/(?:Z|[+-]\d{2}:\d{2})$/u.test(value)) {
    throw invalidWeather('Waktu pembaruan BMKG tidak valid.');
  }
  const parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime())) throw invalidWeather('Waktu pembaruan BMKG tidak valid.');
  return parsed;
}

function normalizeBmkgSnapshot(source, payload, fetchedAt) {
  const now = asDate(fetchedAt);
  if (!now) throw invalidWeather('Waktu pengambilan prakiraan tidak valid.');
  const config = validateWeatherSource(source, now);
  if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw invalidWeather('Data prakiraan BMKG tidak valid.');
  }
  const rainfallMm = parseRainfall(readJsonPath(payload, config.normalization.rainfallMmPath));
  const sourceUpdatedAt = parseSourceUpdatedAt(
    readJsonPath(payload, config.normalization.sourceUpdatedAtPath),
  );
  const id = sha256(JSON.stringify([
    config.rtId,
    config.sourceFingerprint,
    sourceUpdatedAt.toISOString(),
    rainfallMm,
  ])).slice(0, 40);
  return {
    id,
    rtId: config.rtId,
    source: 'BMKG',
    sourceFingerprint: config.sourceFingerprint,
    sourceUpdatedAt,
    fetchedAt: now,
    rainfallMm,
  };
}

function validateWeatherRule(record, expectedRtId, now) {
  const expected = [
    'ruleId', 'version', 'rtId', 'enabled', 'reviewStatus', 'reviewedBy', 'reviewedAt',
    'minimumRainfallMm', 'suggestedTemplateVersions', 'explanation',
  ];
  if (!exactKeys(record, expected) || !RULE_ID_PATTERN.test(record.ruleId || '') ||
      !Number.isInteger(record.version) || record.version < 1 ||
      record.rtId !== expectedRtId || record.enabled !== true ||
      !validReview(record, now) ||
      typeof record.minimumRainfallMm !== 'number' ||
      !Number.isFinite(record.minimumRainfallMm) || record.minimumRainfallMm < 0 ||
      !Array.isArray(record.suggestedTemplateVersions) ||
      record.suggestedTemplateVersions.length < 1 ||
      record.suggestedTemplateVersions.length > MAX_RECOMMENDED_TEMPLATES ||
      typeof record.explanation !== 'string' ||
      record.explanation.normalize('NFC').trim().length === 0 ||
      [...record.explanation].length > 240 ||
      /[\u0000-\u001F\u007F]/u.test(record.explanation)) {
    throw invalidWeather();
  }
  const seen = new Set();
  const suggestedTemplateVersions = record.suggestedTemplateVersions.map((item) => {
    if (!exactKeys(item, ['templateId', 'version', 'fingerprint']) ||
        !TEMPLATE_ID_PATTERN.test(item.templateId || '') ||
        !Number.isInteger(item.version) || item.version < 1 ||
        !/^[a-f0-9]{64}$/u.test(item.fingerprint || '')) throw invalidWeather();
    const key = `${item.templateId}:v${item.version}`;
    if (seen.has(key)) throw invalidWeather();
    seen.add(key);
    return {
      templateId: item.templateId,
      version: item.version,
      fingerprint: item.fingerprint,
    };
  });
  const normalized = {
    ruleId: record.ruleId,
    version: record.version,
    rtId: record.rtId,
    minimumRainfallMm: record.minimumRainfallMm,
    suggestedTemplateVersions,
    explanation: record.explanation.normalize('NFC').trim(),
  };
  return {
    ...normalized,
    ruleFingerprint: sha256(JSON.stringify([
      normalized.ruleId,
      normalized.version,
      normalized.rtId,
      normalized.minimumRainfallMm,
      normalized.suggestedTemplateVersions,
      normalized.explanation,
    ])),
  };
}

function snapshotIsFresh(snapshot, now, maximumAgeSeconds) {
  const sourceUpdatedAt = asDate(snapshot.sourceUpdatedAt);
  const fetchedAt = asDate(snapshot.fetchedAt);
  if (!sourceUpdatedAt || !fetchedAt || !Number.isInteger(maximumAgeSeconds) ||
      maximumAgeSeconds < 1 || sourceUpdatedAt > now || fetchedAt > now) return false;
  const maximumAgeMs = maximumAgeSeconds * 1000;
  return now.getTime() - sourceUpdatedAt.getTime() <= maximumAgeMs &&
    now.getTime() - fetchedAt.getTime() <= maximumAgeMs;
}

function evaluateWeatherRules(snapshot, rules, evaluatedAt, maximumAgeSeconds) {
  const now = asDate(evaluatedAt);
  if (!now || snapshot.source !== 'BMKG' || !snapshotIsFresh(snapshot, now, maximumAgeSeconds)) {
    return [];
  }
  const seenRuleIds = new Set();
  const suggestions = [];
  for (const rule of rules) {
    if (seenRuleIds.has(rule.ruleId)) throw invalidWeather('Kode aturan cuaca duplikat.');
    seenRuleIds.add(rule.ruleId);
    if (rule.rtId !== snapshot.rtId || snapshot.rainfallMm < rule.minimumRainfallMm) continue;
    const suggestionId = sha256(
      `${snapshot.rtId}\0${snapshot.id}\0${snapshot.sourceFingerprint}\0${rule.ruleId}\0${rule.version}\0${rule.ruleFingerprint}`,
    ).slice(0, 40);
    suggestions.push({
      suggestionId,
      rtId: snapshot.rtId,
      source: 'BMKG',
      snapshotId: snapshot.id,
      sourceFingerprint: snapshot.sourceFingerprint,
      sourceUpdatedAt: asDate(snapshot.sourceUpdatedAt),
      fetchedAt: asDate(snapshot.fetchedAt),
      rainfallMm: snapshot.rainfallMm,
      maximumAgeSeconds,
      ruleId: rule.ruleId,
      ruleVersion: rule.version,
      ruleFingerprint: rule.ruleFingerprint,
      recommendedTemplateVersions: rule.suggestedTemplateVersions.map(({ templateId, version }) => ({
        templateId,
        version,
      })),
      explanation: rule.explanation,
      state: 'SUGGESTED',
      createdAt: now,
    });
  }
  return suggestions;
}

function publicWeatherSnapshot(record) {
  if (record == null) return null;
  const sourceUpdatedAt = asDate(record.sourceUpdatedAt);
  const fetchedAt = asDate(record.fetchedAt);
  if (!/^[a-f0-9]{40}$/u.test(record.id || '') ||
      !RT_ID_PATTERN.test(record.rtId || '') || record.source !== 'BMKG' ||
      !sourceUpdatedAt || !fetchedAt || !Number.isFinite(record.rainfallMm) ||
      record.rainfallMm < 0 ||
      (record.maximumAgeSeconds != null &&
        (!Number.isInteger(record.maximumAgeSeconds) ||
          record.maximumAgeSeconds < 60 || record.maximumAgeSeconds > MAX_WEATHER_AGE_SECONDS))) {
    throw invalidWeather('Snapshot cuaca tidak konsisten.');
  }
  return {
    id: record.id,
    source: 'BMKG',
    communityId: record.rtId,
    sourceUpdatedAt: sourceUpdatedAt.toISOString(),
    fetchedAt: fetchedAt.toISOString(),
    rainfallMm: record.rainfallMm,
    maximumAgeSeconds: record.maximumAgeSeconds ?? null,
  };
}

function validateOperatorAuth(auth) {
  if (!auth || typeof auth.operatorUid !== 'string' || !auth.operatorUid.trim() ||
      auth.signInProvider !== 'password') throw permissionDenied();
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowedKeys.includes(key))) {
    throw invalidArgument();
  }
}

function publicSuggestion(record, now) {
  const sourceUpdatedAt = asDate(record.sourceUpdatedAt);
  const fetchedAt = asDate(record.fetchedAt);
  const createdAt = asDate(record.createdAt);
  if (!/^[a-f0-9]{40}$/u.test(record.suggestionId || '') ||
      record.source !== 'BMKG' || record.state !== 'SUGGESTED' ||
      !/^[a-f0-9]{40}$/u.test(record.snapshotId || '') ||
      !/^[a-f0-9]{64}$/u.test(record.sourceFingerprint || '') ||
      !RULE_ID_PATTERN.test(record.ruleId || '') || !Number.isInteger(record.ruleVersion) ||
      record.ruleVersion < 1 || !/^[a-f0-9]{64}$/u.test(record.ruleFingerprint || '') ||
      !sourceUpdatedAt || !fetchedAt || !createdAt ||
      !Number.isFinite(record.rainfallMm) || record.rainfallMm < 0 ||
      !Number.isInteger(record.maximumAgeSeconds) || record.maximumAgeSeconds < 1 ||
      !Array.isArray(record.recommendedTemplateVersions) ||
      typeof record.explanation !== 'string') {
    throw invalidWeather('Saran cuaca tidak konsisten.');
  }
  return {
    suggestionId: record.suggestionId,
    source: 'BMKG',
    snapshotId: record.snapshotId,
    sourceUpdatedAt: sourceUpdatedAt.toISOString(),
    fetchedAt: fetchedAt.toISOString(),
    rainfallMm: record.rainfallMm,
    ruleId: record.ruleId,
    ruleVersion: record.ruleVersion,
    recommendedTemplateVersions: record.recommendedTemplateVersions,
    explanation: record.explanation,
    state: 'SUGGESTED',
    createdAt: createdAt.toISOString(),
    isStale: !snapshotIsFresh({ sourceUpdatedAt, fetchedAt }, now, record.maximumAgeSeconds),
  };
}

class WeatherSuggestionService {
  constructor(repository, { fetchPayload, clock = () => new Date() } = {}) {
    if (typeof fetchPayload !== 'function') throw new TypeError('fetchPayload is required');
    this.repository = repository;
    this.fetchPayload = fetchPayload;
    this.clock = clock;
  }

  async syncConfiguredSources() {
    const sources = await this.repository.listEnabledWeatherSources();
    const result = {
      sourcesScanned: sources.length,
      snapshotsUpdated: 0,
      suggestionsCreated: 0,
      skipped: 0,
      failed: 0,
    };
    for (const source of sources) {
      try {
        const startedAt = this.clock();
        const config = validateWeatherSource(source, startedAt);
        if (source.sourceId !== config.rtId) throw invalidWeather();
        const payload = await this.fetchPayload({ ...config, sourceId: source.sourceId });
        const fetchedAt = this.clock();
        const candidate = normalizeBmkgSnapshot(config, payload, fetchedAt);
        if (candidate.sourceUpdatedAt > fetchedAt ||
            !snapshotIsFresh(candidate, fetchedAt, config.maximumAgeSeconds)) {
          result.skipped += 1;
          continue;
        }
        const persisted = await this.repository.saveSnapshotIfNewer(candidate);
        if (!persisted?.snapshot) throw invalidWeather('Snapshot cuaca tidak konsisten.');
        if (persisted.updated) result.snapshotsUpdated += 1;
        else result.skipped += 1;
        if (persisted.snapshot.sourceFingerprint !== config.sourceFingerprint) {
          if (persisted.updated) result.skipped += 1;
          continue;
        }

        const rawRules = await this.repository.listReviewedWeatherRules(config.rtId);
        const rules = [];
        const ruleIds = new Set();
        for (const rawRule of rawRules) {
          try {
            const reviewedRule = validateWeatherRule(rawRule, config.rtId, fetchedAt);
            if (ruleIds.has(reviewedRule.ruleId)) continue;
            ruleIds.add(reviewedRule.ruleId);
            rules.push(reviewedRule);
          } catch (_) {
            // Unreviewed or malformed configuration fails closed without logging its contents.
          }
        }
        const suggestions = evaluateWeatherRules(
          persisted.snapshot, rules, fetchedAt, config.maximumAgeSeconds,
        );
        result.suggestionsCreated += await this.repository.createSuggestionsIfMissing(suggestions);
      } catch (_) {
        // One bad source must not stop other communities or expose upstream/config details.
        result.failed += 1;
      }
    }
    return result;
  }

  async getLastValidWeatherSnapshotForOperator(auth, data = {}) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const snapshot = await this.repository.getLastValidSnapshotForOperator(auth.operatorUid);
    return { snapshot: publicWeatherSnapshot(snapshot) };
  }

  async getLastValidWeatherSnapshotForRt(rtId) {
    if (typeof rtId !== 'string' || !RT_ID_PATTERN.test(rtId)) {
      throw invalidArgument('Ruang RT tidak valid.');
    }
    const snapshot = await this.repository.getLastValidSnapshotForRt(rtId);
    return { snapshot: publicWeatherSnapshot(snapshot) };
  }

  async listWeatherSuggestions(auth, data = {}) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const rows = await this.repository.listSuggestionsForOperator(auth.operatorUid, {
      limit: MAX_SUGGESTION_PAGE_SIZE,
    });
    const now = this.clock();
    return { suggestions: rows.map((row) => publicSuggestion(row, now)) };
  }
}

module.exports = {
  MAX_SUGGESTION_PAGE_SIZE,
  WeatherPipelineError,
  WeatherSuggestionService,
  evaluateWeatherRules,
  normalizeBmkgSnapshot,
  snapshotIsFresh,
  validateBmkgEndpoint,
  validateWeatherRule,
  validateWeatherSource,
};
