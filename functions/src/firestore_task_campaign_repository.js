const { Timestamp } = require('firebase-admin/firestore');
const {
  OPERATOR_ROLES,
  TASK_CATEGORIES,
  TASK_LOCATION_REFERENCES,
  TaskCampaignError,
  approvedTemplateFromRecord,
  asDate,
  publicTemplate,
  templateDocumentId,
  templateFingerprint,
} = require('./task_campaign_service');
const { validateTaskNotificationPolicy } = require('./task_notification_policy');

function denyOperator() {
  return new TaskCampaignError('permission-denied', 'Akses operator tidak valid.');
}

function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true || !OPERATOR_ROLES.has(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) {
    throw denyOperator();
  }
  return { rtId: data.rtId.trim(), role: data.role };
}

function templateFromSnapshot(snapshot, templateId, version) {
  if (!snapshot.exists) return null;
  return approvedTemplateFromRecord(snapshot.data(), templateId, version);
}

const MAX_ACTIVE_CAMPAIGNS = 200;

function campaignTemplateSnapshot(value) {
  const allowedKeys = new Set([
    'templateId', 'version', 'title', 'category', 'coreInstruction',
    'safetyInstruction', 'estimatedDurationMinutes',
  ]);
  const requiredTextValue = (text, maxLength) => typeof text === 'string' &&
    text === text.normalize('NFC').trim() && text.length > 0 && [...text].length <= maxLength;
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some((key) => !allowedKeys.has(key)) ||
      typeof value.templateId !== 'string' || !/^[a-z][a-z0-9_-]{0,63}$/u.test(value.templateId) ||
      !Number.isInteger(value.version) || value.version < 1 ||
      !requiredTextValue(value.title, 120) || !TASK_CATEGORIES.has(value.category) ||
      !requiredTextValue(value.coreInstruction, 3000) ||
      !requiredTextValue(value.safetyInstruction, 3000) ||
      (Object.hasOwn(value, 'estimatedDurationMinutes') &&
        (!Number.isInteger(value.estimatedDurationMinutes) ||
          value.estimatedDurationMinutes < 1 || value.estimatedDurationMinutes > 480))) {
    throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
  }
  return {
    templateId: value.templateId,
    version: value.version,
    title: value.title,
    category: value.category,
    coreInstruction: value.coreInstruction,
    safetyInstruction: value.safetyInstruction,
    ...(Object.hasOwn(value, 'estimatedDurationMinutes') ? {
      estimatedDurationMinutes: value.estimatedDurationMinutes,
    } : {}),
  };
}

function historyTimestampParts(value) {
  if (value instanceof Date) {
    const millis = value.getTime();
    if (!Number.isFinite(millis)) return null;
    const seconds = Math.floor(millis / 1000);
    return {
      date: value,
      seconds,
      nanoseconds: (millis - seconds * 1000) * 1000000,
    };
  }
  if (!value || !Number.isInteger(value.seconds) || !Number.isInteger(value.nanoseconds) ||
      value.nanoseconds < 0 || value.nanoseconds > 999999999 ||
      value.seconds < -62135596800 || value.seconds > 253402300799 ||
      typeof value.toDate !== 'function') return null;
  const date = value.toDate();
  if (!(date instanceof Date) || !Number.isFinite(date.getTime())) return null;
  return { date, seconds: value.seconds, nanoseconds: value.nanoseconds };
}

function historyCampaignFromSnapshot(snapshot, rtId) {
  const campaign = snapshot.data();
  if (!campaign || typeof campaign !== 'object' || Array.isArray(campaign)) {
    throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
  }
  const activatedAt = historyTimestampParts(campaign.activatedAt);
  const deadline = historyTimestampParts(campaign.deadline);
  const cancelledAt = campaign.cancelledAt == null
    ? null : historyTimestampParts(campaign.cancelledAt);
  const closedAt = campaign.closedAt == null
    ? null : historyTimestampParts(campaign.closedAt);
  const templateSnapshot = campaignTemplateSnapshot(campaign.templateSnapshot);
  if (snapshot.id !== campaign.campaignId || !/^[a-f0-9]{40}$/u.test(snapshot.id) ||
      campaign.rtId !== rtId || !['ACTIVE', 'CLOSED', 'CANCELLED'].includes(campaign.status) ||
      !activatedAt || !deadline ||
      (campaign.cancelledAt != null && !cancelledAt) ||
      (campaign.closedAt != null && !closedAt) ||
      (campaign.locationReference != null &&
        !TASK_LOCATION_REFERENCES.has(campaign.locationReference)) ||
      (campaign.status === 'ACTIVE' && (cancelledAt !== null || closedAt !== null)) ||
      (campaign.status === 'CLOSED' &&
        (!closedAt || closedAt.date < activatedAt.date || cancelledAt !== null)) ||
      (campaign.status === 'CANCELLED' &&
        (!cancelledAt || cancelledAt.date < activatedAt.date || closedAt !== null)) ||
      campaign.templateId !== templateSnapshot.templateId ||
      campaign.templateVersion !== templateSnapshot.version ||
      campaign.templateFingerprint !== templateFingerprint(templateSnapshot)) {
    throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
  }
  return {
    campaignId: campaign.campaignId,
    templateSnapshot,
    deadline: deadline.date,
    locationReference: campaign.locationReference ?? null,
    status: campaign.status,
    activatedAt: activatedAt.date,
    cancelledAt: cancelledAt?.date ?? null,
    closedAt: closedAt?.date ?? null,
    cursor: {
      seconds: activatedAt.seconds,
      nanoseconds: activatedAt.nanoseconds,
      campaignId: campaign.campaignId,
    },
  };
}

function campaignTemplateMatches(campaign, template) {
  if (!campaign || !template || campaign.templateFingerprint !== template.fingerprint ||
      !campaign.templateSnapshot || typeof campaign.templateSnapshot !== 'object') {
    return false;
  }
  const expected = publicTemplate(template);
  const actual = campaign.templateSnapshot;
  return JSON.stringify(Object.keys(expected).sort().map((key) => [key, expected[key]])) ===
    JSON.stringify(Object.keys(actual).sort().map((key) => [key, actual[key]]));
}

class FirestoreTaskCampaignRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async listApprovedTemplates(operatorUid) {
    const operatorSnapshot = await this.firestore.collection('operators').doc(operatorUid).get();
    requireOperator(operatorSnapshot);

    const templates = await this.firestore.collection('task_templates')
      .where('reviewStatus', '==', 'approved')
      .get();
    return templates.docs
      .map((snapshot) => {
        const record = snapshot.data();
        if (snapshot.id !== templateDocumentId(record.templateId, record.version)) {
          return null;
        }
        return approvedTemplateFromRecord(record, record.templateId, record.version);
      })
      .filter((template) => template !== null)
      .sort((left, right) => left.templateId.localeCompare(right.templateId))
      .map((template) => ({
        templateId: template.templateId,
        version: template.version,
        title: template.title,
        category: template.category,
        coreInstruction: template.coreInstruction,
        safetyInstruction: template.safetyInstruction,
        ...(template.estimatedDurationMinutes == null ? {} : {
          estimatedDurationMinutes: template.estimatedDurationMinutes,
        }),
        fingerprint: template.fingerprint,
      }));
  }

  async listRtTaskHistory(operatorUid, { pageSize, cursor }) {
    const operatorRef = this.firestore.collection('operators').doc(operatorUid);
    return this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      let query = this.firestore.collection('task_campaigns')
        .where('rtId', '==', operator.rtId)
        .where('status', 'in', ['ACTIVE', 'CLOSED', 'CANCELLED'])
        .orderBy('activatedAt', 'desc')
        .orderBy('campaignId', 'desc');
      if (cursor) {
        query = query.startAfter(
          new Timestamp(cursor.seconds, cursor.nanoseconds),
          cursor.campaignId,
        );
      }
      const historySnapshot = await transaction.get(query.limit(pageSize + 1));
      const rows = historySnapshot.docs.map((snapshot) =>
        historyCampaignFromSnapshot(snapshot, operator.rtId));
      const hasMore = rows.length > pageSize;
      const visibleRows = hasMore ? rows.slice(0, pageSize) : rows;
      return {
        tasks: visibleRows.map(({ cursor: ignored, ...task }) => task),
        nextCursor: hasMore ? visibleRows[visibleRows.length - 1].cursor : null,
      };
    });
  }

  async listActiveCampaigns(operatorUid) {
    const operatorRef = this.firestore.collection('operators').doc(operatorUid);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      const query = this.firestore.collection('task_campaigns')
        .where('rtId', '==', operator.rtId)
        .where('status', '==', 'ACTIVE')
        .orderBy('deadline', 'asc')
        .limit(MAX_ACTIVE_CAMPAIGNS + 1);
      const campaignsSnapshot = await transaction.get(query);
      if (campaignsSnapshot.size > MAX_ACTIVE_CAMPAIGNS) {
        throw new TaskCampaignError(
          'failed-precondition',
          'Daftar tugas aktif terlalu panjang untuk dimuat.',
        );
      }
      result = campaignsSnapshot.docs.map((snapshot) => {
        const campaign = snapshot.data();
        const deadline = asDate(campaign.deadline);
        if (snapshot.id !== campaign.campaignId || campaign.rtId !== operator.rtId ||
            campaign.status !== 'ACTIVE' || !deadline ||
            (campaign.locationReference != null &&
              !TASK_LOCATION_REFERENCES.has(campaign.locationReference))) {
          throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
        }
        return {
          campaignId: campaign.campaignId,
          templateSnapshot: campaignTemplateSnapshot(campaign.templateSnapshot),
          deadline,
          locationReference: campaign.locationReference ?? null,
        };
      });
    });
    return result;
  }

  async createDraft(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const templateRef = this.firestore.collection('task_templates')
      .doc(templateDocumentId(input.templateId, input.version));
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const templateSnapshot = await transaction.get(templateRef);
      const campaignSnapshot = await transaction.get(campaignRef);
      const operator = requireOperator(operatorSnapshot);
      if (campaignSnapshot.exists) {
        const existing = campaignSnapshot.data();
        if (existing.createdByOperatorUid !== input.operatorUid ||
            existing.rtId !== operator.rtId ||
            existing.requestFingerprint !== input.requestFingerprint ||
            !['DRAFT', 'ACTIVE'].includes(existing.status)) {
          throw new TaskCampaignError(
            'already-exists',
            'Permintaan pembuatan tugas sudah digunakan.',
          );
        }
        result = existing;
        return;
      }

      const template = templateFromSnapshot(templateSnapshot, input.templateId, input.version);
      if (!template) {
        throw new TaskCampaignError(
          'failed-precondition',
          'Template belum disetujui atau tidak aktif.',
        );
      }
      if (!(input.deadline instanceof Date) || input.deadline.getTime() <= input.now.getTime()) {
        throw new TaskCampaignError('invalid-argument', 'Batas waktu tugas harus di masa depan.');
      }

      result = {
        campaignId: input.campaignId,
        rtId: operator.rtId,
        templateId: template.templateId,
        templateVersion: template.version,
        templateFingerprint: template.fingerprint,
        templateSnapshot: publicTemplate(template),
        deadline: input.deadline,
        locationReference: input.locationReference,
        status: 'DRAFT',
        createdByOperatorUid: input.operatorUid,
        createdAt: input.now,
        requestFingerprint: input.requestFingerprint,
      };
      transaction.create(campaignRef, result);
    });
    return result;
  }

  async activateCampaign(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    const auditRef = this.firestore.collection('task_audit_events')
      .doc(`${input.campaignId}_activated`);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const campaignSnapshot = await transaction.get(campaignRef);
      const operator = requireOperator(operatorSnapshot);
      if (!campaignSnapshot.exists) {
        throw new TaskCampaignError('not-found', 'Tugas tidak ditemukan.');
      }
      const campaign = campaignSnapshot.data();
      if (campaign.rtId !== operator.rtId) throw denyOperator();
      const auditSnapshot = await transaction.get(auditRef);

      if (campaign.status === 'ACTIVE') {
        if (campaign.activationCommandHash === input.commandHash &&
            campaign.activatedByOperatorUid === input.operatorUid &&
            auditSnapshot.exists &&
            auditSnapshot.data().actorUid === input.operatorUid &&
            auditSnapshot.data().commandHash === input.commandHash) {
          result = campaign;
          return;
        }
        throw new TaskCampaignError('failed-precondition', 'Tugas sudah diaktifkan.');
      }
      if (campaign.status !== 'DRAFT') {
        throw new TaskCampaignError('failed-precondition', 'Hanya draf yang dapat diaktifkan.');
      }
      if (auditSnapshot.exists) {
        throw new TaskCampaignError('failed-precondition', 'Riwayat aktivasi tidak konsisten.');
      }
      const deadline = asDate(campaign.deadline);
      if (!deadline || deadline.getTime() <= input.now.getTime()) {
        throw new TaskCampaignError('failed-precondition', 'Batas waktu tugas sudah lewat.');
      }

      const templateRef = this.firestore.collection('task_templates')
        .doc(templateDocumentId(campaign.templateId, campaign.templateVersion));
      const templateSnapshot = await transaction.get(templateRef);
      const template = templateFromSnapshot(
        templateSnapshot,
        campaign.templateId,
        campaign.templateVersion,
      );
      if (!campaignTemplateMatches(campaign, template)) {
        throw new TaskCampaignError(
          'failed-precondition',
          'Template berubah, dinonaktifkan, atau tidak lagi disetujui.',
        );
      }

      let notificationPolicy = null;
      const communityRef = this.firestore.collection('rt_communities').doc(operator.rtId);
      const communitySnapshot = await transaction.get(communityRef);
      const policyDocumentId = communitySnapshot.data()?.reminderPolicyId;
      if (typeof policyDocumentId === 'string' &&
          /^[A-Za-z0-9_-]{1,120}$/u.test(policyDocumentId)) {
        const policyRef = this.firestore.collection('task_reminder_policies').doc(policyDocumentId);
        const policySnapshot = await transaction.get(policyRef);
        if (policySnapshot.exists) {
          try {
            notificationPolicy = validateTaskNotificationPolicy(
              policySnapshot.data(), policySnapshot.id, operator.rtId,
            );
          } catch (_) {
            // Missing or malformed policy disables notifications, never campaign activation.
          }
        }
      }

      const activated = {
        ...campaign,
        status: 'ACTIVE',
        activatedAt: input.now,
        activatedByOperatorUid: input.operatorUid,
        activationCommandHash: input.commandHash,
        notificationPolicyDocumentId: notificationPolicy?.policyDocumentId ?? null,
        notificationPolicyVersion: notificationPolicy?.version ?? null,
        notificationPolicyFingerprint: notificationPolicy?.fingerprint ?? null,
      };
      transaction.update(campaignRef, {
        status: activated.status,
        activatedAt: activated.activatedAt,
        activatedByOperatorUid: activated.activatedByOperatorUid,
        activationCommandHash: activated.activationCommandHash,
        notificationPolicyDocumentId: activated.notificationPolicyDocumentId,
        notificationPolicyVersion: activated.notificationPolicyVersion,
        notificationPolicyFingerprint: activated.notificationPolicyFingerprint,
      });
      transaction.create(auditRef, {
        campaignId: input.campaignId,
        rtId: operator.rtId,
        action: 'CAMPAIGN_ACTIVATED',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        templateId: campaign.templateId,
        templateVersion: campaign.templateVersion,
        occurredAt: input.now,
      });
      result = activated;
    });
    return result;
  }

  async closeCampaign(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.taskId);
    const auditRef = this.firestore.collection('task_audit_events')
      .doc(`${input.taskId}_closed`);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, campaignSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef),
        transaction.get(campaignRef),
        transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (!campaignSnapshot.exists) throw denyOperator();
      const campaign = campaignSnapshot.data();
      if (campaign.rtId !== operator.rtId) throw denyOperator();
      if (campaign.campaignId !== input.taskId) {
        throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
      }
      const audit = auditSnapshot.exists ? auditSnapshot.data() : null;
      if (campaign.status === 'CLOSED') {
        const closedAt = asDate(campaign.closedAt);
        const auditAt = asDate(audit?.occurredAt);
        if (campaign.closureCommandHash === input.commandHash &&
            campaign.closedByOperatorUid === input.operatorUid &&
            audit?.campaignId === input.taskId && audit.rtId === operator.rtId &&
            audit.action === 'CAMPAIGN_CLOSED' &&
            audit.actorUid === input.operatorUid && audit.commandHash === input.commandHash &&
            closedAt && auditAt && closedAt.getTime() === auditAt.getTime()) {
          result = campaign;
          return;
        }
        throw new TaskCampaignError('failed-precondition', 'Tugas sudah ditutup.');
      }
      if (campaign.status !== 'ACTIVE') {
        throw new TaskCampaignError('failed-precondition', 'Hanya tugas aktif yang dapat ditutup.');
      }
      const activatedAt = asDate(campaign.activatedAt);
      if (!activatedAt || input.now < activatedAt) {
        throw new TaskCampaignError('failed-precondition', 'Waktu penutupan tidak konsisten.');
      }
      if (auditSnapshot.exists) {
        throw new TaskCampaignError('failed-precondition', 'Riwayat penutupan tidak konsisten.');
      }

      const closed = {
        ...campaign,
        status: 'CLOSED',
        closedAt: input.now,
        closedByOperatorUid: input.operatorUid,
        closureCommandHash: input.commandHash,
      };
      transaction.update(campaignRef, {
        status: closed.status,
        closedAt: closed.closedAt,
        closedByOperatorUid: closed.closedByOperatorUid,
        closureCommandHash: closed.closureCommandHash,
      });
      transaction.create(auditRef, {
        campaignId: input.taskId,
        rtId: operator.rtId,
        action: 'CAMPAIGN_CLOSED',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        occurredAt: input.now,
      });
      result = closed;
    });
    return result;
  }

  async listTaskLifecycleEvents(operatorUid, taskId) {
    const operatorRef = this.firestore.collection('operators').doc(operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(taskId);
    const lifecycle = [
      { suffix: 'activated', action: 'CAMPAIGN_ACTIVATED', eventType: 'ACTIVATED', field: 'activatedAt', actorField: 'activatedByOperatorUid', commandField: 'activationCommandHash' },
      { suffix: 'closed', action: 'CAMPAIGN_CLOSED', eventType: 'CLOSED', field: 'closedAt', actorField: 'closedByOperatorUid', commandField: 'closureCommandHash' },
      { suffix: 'cancelled', action: 'CAMPAIGN_CANCELLED', eventType: 'CANCELLED', field: 'cancelledAt', actorField: 'cancelledByOperatorUid', commandField: 'cancellationCommandHash' },
    ];
    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, campaignSnapshot] = await Promise.all([
        transaction.get(operatorRef),
        transaction.get(campaignRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (!campaignSnapshot.exists || campaignSnapshot.data()?.rtId !== operator.rtId) {
        throw denyOperator();
      }
      const history = historyCampaignFromSnapshot(campaignSnapshot, operator.rtId);
      const auditRefs = lifecycle.map(({ suffix }) =>
        this.firestore.collection('task_audit_events').doc(`${taskId}_${suffix}`));
      const auditSnapshots = await Promise.all(auditRefs.map((reference) =>
        transaction.get(reference)));
      const events = [];
      for (let index = 0; index < lifecycle.length; index += 1) {
        const snapshot = auditSnapshots[index];
        if (!snapshot.exists) continue;
        const definition = lifecycle[index];
        const audit = snapshot.data();
        const occurredAt = asDate(audit?.occurredAt);
        const campaignEventAt = asDate(campaignSnapshot.data()?.[definition.field]);
        if (audit?.campaignId !== taskId || audit.rtId !== operator.rtId ||
            audit.action !== definition.action ||
            audit.actorUid !== campaignSnapshot.data()?.[definition.actorField] ||
            !/^[a-f0-9]{64}$/u.test(audit.commandHash || '') ||
            audit.commandHash !== campaignSnapshot.data()?.[definition.commandField] ||
            !occurredAt || !campaignEventAt ||
            occurredAt.getTime() !== campaignEventAt.getTime()) {
          throw new TaskCampaignError('failed-precondition', 'Riwayat perubahan tugas tidak konsisten.');
        }
        events.push({ eventType: definition.eventType, occurredAt });
      }
      const expectedTypes = history.status === 'ACTIVE' ? ['ACTIVATED']
        : history.status === 'CLOSED' ? ['ACTIVATED', 'CLOSED']
          : ['ACTIVATED', 'CANCELLED'];
      events.sort((left, right) => left.occurredAt - right.occurredAt);
      if (JSON.stringify(events.map((event) => event.eventType)) !==
          JSON.stringify(expectedTypes)) {
        throw new TaskCampaignError('failed-precondition', 'Riwayat perubahan tugas tidak konsisten.');
      }
      return events;
    });
  }

  async cancelCampaign(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.taskId);
    const auditRef = this.firestore.collection('task_audit_events')
      .doc(`${input.taskId}_cancelled`);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, campaignSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef),
        transaction.get(campaignRef),
        transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      // Treat absent and foreign-RT task IDs alike so this endpoint cannot probe other RTs.
      if (!campaignSnapshot.exists) throw denyOperator();
      const campaign = campaignSnapshot.data();
      if (campaign.rtId !== operator.rtId) throw denyOperator();
      if (campaign.campaignId !== input.taskId) {
        throw new TaskCampaignError('failed-precondition', 'Data tugas tidak konsisten.');
      }
      const audit = auditSnapshot.exists ? auditSnapshot.data() : null;

      if (campaign.status === 'CANCELLED') {
        if (campaign.cancellationCommandHash === input.commandHash &&
            campaign.cancelledByOperatorUid === input.operatorUid &&
            audit?.campaignId === input.taskId && audit.rtId === operator.rtId &&
            audit.action === 'CAMPAIGN_CANCELLED' &&
            audit.actorUid === input.operatorUid && audit.commandHash === input.commandHash &&
            asDate(campaign.cancelledAt) && asDate(audit.occurredAt)) {
          result = campaign;
          return;
        }
        throw new TaskCampaignError('failed-precondition', 'Tugas sudah dibatalkan.');
      }
      if (campaign.status !== 'ACTIVE') {
        throw new TaskCampaignError('failed-precondition', 'Hanya tugas aktif yang dapat dibatalkan.');
      }
      if (auditSnapshot.exists) {
        throw new TaskCampaignError('failed-precondition', 'Riwayat pembatalan tidak konsisten.');
      }

      const cancelled = {
        ...campaign,
        status: 'CANCELLED',
        cancelledAt: input.now,
        cancelledByOperatorUid: input.operatorUid,
        cancellationCommandHash: input.commandHash,
      };
      transaction.update(campaignRef, {
        status: cancelled.status,
        cancelledAt: cancelled.cancelledAt,
        cancelledByOperatorUid: cancelled.cancelledByOperatorUid,
        cancellationCommandHash: cancelled.cancellationCommandHash,
      });
      transaction.create(auditRef, {
        campaignId: input.taskId,
        rtId: operator.rtId,
        action: 'CAMPAIGN_CANCELLED',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        occurredAt: input.now,
      });
      result = cancelled;
    });
    return result;
  }
}

module.exports = { FirestoreTaskCampaignRepository };
