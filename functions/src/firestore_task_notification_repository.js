const { FieldValue } = require('firebase-admin/firestore');
const { OPERATOR_ROLES } = require('./task_campaign_service');
const { responseDocumentId } = require('./task_response_service');
const {
  cohortMatches,
  toDate,
  validateTaskNotificationPolicy,
} = require('./task_notification_policy');
const {
  notificationEventId,
  pendampingRecipientHash,
  residentNotificationRecipientHash,
  tokenDocumentId,
} = require('./task_notification_id');

const POLICY_COLLECTION = 'task_reminder_policies';
const EVENT_COLLECTION = 'task_notification_events';
const AUDIT_COLLECTION = 'task_notification_audit_events';
const RESIDENT_TOKEN_COLLECTION = 'resident_push_tokens';
const OPERATOR_TOKEN_COLLECTION = 'operator_push_tokens';
const MAX_POLICIES = 500;
const MAX_CAMPAIGNS_PER_RT = 200;
const MAX_RESIDENTS_PER_RT = 500;
const MAX_DUE_EVENTS = 250;
const DELIVERY_LEASE_MS = 2 * 60 * 1000;
const TASK_ID_PATTERN = /^[a-f0-9]{40}$/u;
const POLICY_DOCUMENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,120}$/u;
const HASH_PATTERN = /^[a-f0-9]{64}$/u;
const WINDOW_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/u;

class TaskNotificationError extends Error {
  constructor(code, message = 'Notifikasi tugas tidak dapat diproses.') {
    super(message);
    this.name = 'TaskNotificationError';
    this.code = code;
  }
}

function deny() {
  throw new TaskNotificationError('permission-denied', 'Akses operator tidak valid.');
}
function invalidData() {
  throw new TaskNotificationError('failed-precondition', 'Data notifikasi tidak konsisten.');
}
function requireOperator(snapshot) {
  const operator = snapshot.data();
  if (!snapshot.exists || operator?.active !== true || !OPERATOR_ROLES.has(operator.role) ||
      typeof operator.rtId !== 'string' || !operator.rtId.trim()) deny();
  return { ...operator, rtId: operator.rtId.trim() };
}
function responseFor(snapshot, responseId, campaignId, rtId, residentId) {
  if (!snapshot.exists) return null;
  const response = snapshot.data();
  if (snapshot.id !== responseId || response?.responseId !== responseId ||
      response.taskId !== campaignId || response.rtId !== rtId ||
      response.residentId !== residentId ||
      !['UNRESPONDED', 'JOINED', 'DECLINED'].includes(response.participationState) ||
      !['NOT_SUBMITTED', 'PENDING_RT_VERIFICATION', 'VERIFIED_COMPLETE'].includes(
        response.completionState,
      )) return undefined;
  return response;
}
function validCampaignForPolicy(
  campaignSnapshot, campaignId, policy, policyFingerprint, now, communitySnapshot,
) {
  if (!campaignSnapshot.exists || campaignSnapshot.id !== campaignId ||
      !communitySnapshot?.exists ||
      communitySnapshot.data()?.reminderPolicyId !== policy.policyDocumentId) return null;
  const campaign = campaignSnapshot.data();
  const deadline = toDate(campaign.deadline);
  if (campaign.campaignId !== campaignId || campaign.rtId !== policy.rtId ||
      campaign.status !== 'ACTIVE' || !deadline || deadline <= now ||
      campaign.notificationPolicyDocumentId !== policy.policyDocumentId ||
      campaign.notificationPolicyVersion !== policy.version ||
      campaign.notificationPolicyFingerprint !== policyFingerprint) return null;
  return { ...campaign, deadline };
}
function readPolicy(snapshot, docId, rtId, expectedFingerprint = null) {
  if (!snapshot.exists) return null;
  try {
    const policy = validateTaskNotificationPolicy(snapshot.data(), docId, rtId);
    if (expectedFingerprint && policy.fingerprint !== expectedFingerprint) return null;
    return policy;
  } catch (_) {
    return null;
  }
}
function expectedAudit(event) {
  return {
    eventId: event.eventId,
    rtId: event.rtId,
    campaignId: event.campaignId,
    eventType: event.eventType,
    policyDocumentId: event.policyDocumentId,
    policyVersion: event.policyVersion,
    windowId: event.windowId,
    action: event.eventType === 'TASK_REMINDER'
      ? 'TASK_REMINDER_SCHEDULED' : 'TASK_ESCALATION_SCHEDULED',
  };
}
function assertExistingEvent(eventSnapshot, auditSnapshot, expected) {
  if (!eventSnapshot.exists || !auditSnapshot.exists) invalidData();
  const event = eventSnapshot.data();
  const audit = auditSnapshot.data();
  for (const [field, value] of Object.entries(expected)) {
    if (event[field] !== value) invalidData();
  }
  for (const [field, value] of Object.entries(expectedAudit(event))) {
    if (audit[field] !== value) invalidData();
  }
  return event;
}
function validateToken(token) {
  if (typeof token !== 'string' || token.trim() !== token || token.length < 20 ||
      token.length > 4096 || /\s/u.test(token)) {
    throw new TaskNotificationError('invalid-argument', 'Token perangkat tidak valid.');
  }
  return token;
}

class FirestoreTaskNotificationRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async readActivationPolicy(transaction, rtId) {
    const communityRef = this.firestore.collection('rt_communities').doc(rtId);
    const communitySnapshot = await transaction.get(communityRef);
    const policyDocumentId = communitySnapshot.data()?.reminderPolicyId;
    if (!communitySnapshot.exists || typeof policyDocumentId !== 'string' ||
        !POLICY_DOCUMENT_ID_PATTERN.test(policyDocumentId)) return null;
    const policyRef = this.firestore.collection(POLICY_COLLECTION).doc(policyDocumentId);
    const policySnapshot = await transaction.get(policyRef);
    return readPolicy(policySnapshot, policyDocumentId, rtId);
  }

  async listEnabledPolicies() {
    const snapshot = await this.firestore.collection(POLICY_COLLECTION)
      .where('enabled', '==', true).limit(MAX_POLICIES + 1).get();
    if (snapshot.size > MAX_POLICIES) {
      throw new TaskNotificationError('resource-exhausted', 'Daftar kebijakan notifikasi terlalu besar.');
    }
    const result = [];
    for (const policySnapshot of snapshot.docs) {
      const raw = policySnapshot.data();
      const rtId = raw?.rtId;
      const policy = readPolicy(policySnapshot, policySnapshot.id, rtId);
      if (!policy) continue;
      const communitySnapshot = await this.firestore.collection('rt_communities').doc(rtId).get();
      if (!communitySnapshot.exists || communitySnapshot.data()?.reminderPolicyId !== policySnapshot.id) {
        continue;
      }
      result.push(policy);
    }
    return result;
  }

  async listActiveCampaigns(rtId) {
    const snapshot = await this.firestore.collection('task_campaigns')
      .where('rtId', '==', rtId)
      .where('status', '==', 'ACTIVE')
      .limit(MAX_CAMPAIGNS_PER_RT + 1).get();
    if (snapshot.size > MAX_CAMPAIGNS_PER_RT) {
      throw new TaskNotificationError('resource-exhausted', 'Terlalu banyak tugas aktif untuk diproses.');
    }
    return snapshot.docs.map((document) => ({ ...document.data(), campaignId: document.id }))
      .filter((campaign) => campaign.rtId === rtId && campaign.status === 'ACTIVE' &&
        TASK_ID_PATTERN.test(campaign.campaignId));
  }

  async listResidentStates(rtId, campaignId) {
    const profiles = await this.firestore.collection('resident_profiles')
      .where('rtId', '==', rtId)
      .limit(MAX_RESIDENTS_PER_RT + 1).get();
    if (profiles.size > MAX_RESIDENTS_PER_RT) {
      throw new TaskNotificationError('resource-exhausted', 'Daftar warga RT terlalu besar untuk diproses.');
    }
    const residents = profiles.docs.filter((profile) => {
      const record = profile.data();
      return record.rtId === rtId && record.deletionPending !== true &&
        typeof record.nickname === 'string' && record.nickname.trim().length > 0;
    });
    const responseRefs = residents.map((profile) => this.firestore.collection('task_responses')
      .doc(responseDocumentId(rtId, campaignId, profile.id)));
    const responseSnapshots = responseRefs.length === 0
      ? [] : await this.firestore.getAll(...responseRefs);
    return residents.map((profile, index) => {
      const responseId = responseDocumentId(rtId, campaignId, profile.id);
      const response = responseFor(responseSnapshots[index], responseId, campaignId, rtId, profile.id);
      return {
        residentId: profile.id,
        recipientHash: residentNotificationRecipientHash(rtId, profile.id),
        response,
        valid: response !== undefined,
      };
    });
  }

  async createReminderEvent(input) {
    const eventId = notificationEventId({
      rtId: input.rtId,
      campaignId: input.campaignId,
      eventType: 'TASK_REMINDER',
      windowId: input.window.windowId,
      recipientHash: input.recipientHash,
    });
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    const policyRef = this.firestore.collection(POLICY_COLLECTION).doc(input.policy.policyDocumentId);
    const communityRef = this.firestore.collection('rt_communities').doc(input.rtId);
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    const responseId = responseDocumentId(input.rtId, input.campaignId, input.residentId);
    const responseRef = this.firestore.collection('task_responses').doc(responseId);
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(eventId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(eventId);
    let created = false;
    await this.firestore.runTransaction(async (transaction) => {
      const [campaignSnapshot, policySnapshot, communitySnapshot, residentSnapshot,
        responseSnapshot, eventSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(campaignRef), transaction.get(policyRef), transaction.get(communityRef),
        transaction.get(residentRef), transaction.get(responseRef), transaction.get(eventRef),
        transaction.get(auditRef),
      ]);
      const policy = readPolicy(
        policySnapshot, input.policy.policyDocumentId, input.rtId, input.policy.fingerprint,
      );
      if (!policy || !validCampaignForPolicy(
        campaignSnapshot, input.campaignId, policy, input.policy.fingerprint, input.now,
        communitySnapshot,
      )) return;
      const resident = residentSnapshot.data();
      if (!residentSnapshot.exists || residentSnapshot.id !== input.residentId ||
          resident.rtId !== input.rtId || resident.deletionPending === true ||
          residentNotificationRecipientHash(input.rtId, input.residentId) !== input.recipientHash) return;
      const response = responseFor(responseSnapshot, responseId, input.campaignId, input.rtId,
        input.residentId);
      if (response === undefined || !cohortMatches(input.window.cohort, response)) return;
      const campaign = campaignSnapshot.data();
      const deadline = toDate(campaign.deadline);
      const dueAt = new Date(deadline.getTime() - input.window.minutesBeforeDeadline * 60_000);
      if (input.now < dueAt || input.now >= deadline) return;
      const expected = {
        eventId, rtId: input.rtId, campaignId: input.campaignId,
        eventType: 'TASK_REMINDER', policyDocumentId: policy.policyDocumentId,
        policyVersion: policy.version, policyFingerprint: policy.fingerprint,
        windowId: input.window.windowId, recipientKind: 'RESIDENT',
        recipientHash: input.recipientHash, cohort: input.window.cohort,
      };
      if (eventSnapshot.exists || auditSnapshot.exists) {
        assertExistingEvent(eventSnapshot, auditSnapshot, expected);
        return;
      }
      const event = {
        ...expected,
        minutesBeforeDeadline: input.window.minutesBeforeDeadline,
        deliveryRetrySeconds: policy.deliveryRetrySeconds,
        status: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: input.now,
        createdAt: input.now,
      };
      transaction.create(eventRef, event);
      transaction.create(auditRef, {
        ...expectedAudit(event),
        actor: 'SYSTEM_SCHEDULER',
        occurredAt: input.now,
      });
      created = true;
    });
    return { eventId, created };
  }

  async createEscalationEvent(input) {
    const recipientHash = pendampingRecipientHash(input.rtId);
    const eventId = notificationEventId({
      rtId: input.rtId,
      campaignId: input.campaignId,
      eventType: 'TASK_ESCALATION',
      windowId: input.escalation.windowId,
      recipientHash,
    });
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    const policyRef = this.firestore.collection(POLICY_COLLECTION).doc(input.policy.policyDocumentId);
    const communityRef = this.firestore.collection('rt_communities').doc(input.rtId);
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(eventId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(eventId);
    let created = false;
    await this.firestore.runTransaction(async (transaction) => {
      const [campaignSnapshot, policySnapshot, communitySnapshot, eventSnapshot, auditSnapshot] =
        await Promise.all([
          transaction.get(campaignRef), transaction.get(policyRef), transaction.get(communityRef),
          transaction.get(eventRef), transaction.get(auditRef),
        ]);
      const policy = readPolicy(
        policySnapshot, input.policy.policyDocumentId, input.rtId, input.policy.fingerprint,
      );
      if (!policy || !validCampaignForPolicy(
        campaignSnapshot, input.campaignId, policy, input.policy.fingerprint, input.now,
        communitySnapshot,
      )) return;
      const escalation = policy.escalation;
      if (!escalation.enabled || escalation.windowId !== input.escalation.windowId ||
          escalation.cohort !== input.escalation.cohort ||
          escalation.minimumCohortSize !== input.escalation.minimumCohortSize) return;
      const campaign = campaignSnapshot.data();
      const deadline = toDate(campaign.deadline);
      const dueAt = deadline && new Date(deadline.getTime() -
        escalation.minutesBeforeDeadline * 60_000);
      if (!deadline || !dueAt || input.now < dueAt || input.now >= deadline) return;
      const expected = {
        eventId, rtId: input.rtId, campaignId: input.campaignId,
        eventType: 'TASK_ESCALATION', policyDocumentId: policy.policyDocumentId,
        policyVersion: policy.version, policyFingerprint: policy.fingerprint,
        windowId: escalation.windowId, recipientKind: 'PENDAMPING_RT',
        recipientHash,
      };
      if (eventSnapshot.exists || auditSnapshot.exists) {
        assertExistingEvent(eventSnapshot, auditSnapshot, expected);
        return;
      }
      const event = {
        ...expected,
        cohort: escalation.cohort,
        minimumCohortSize: escalation.minimumCohortSize,
        minutesBeforeDeadline: escalation.minutesBeforeDeadline,
        deliveryRetrySeconds: policy.deliveryRetrySeconds,
        status: 'PENDING',
        attemptCount: 0,
        nextAttemptAt: input.now,
        createdAt: input.now,
      };
      transaction.create(eventRef, event);
      transaction.create(auditRef, {
        ...expectedAudit(event),
        actor: 'SYSTEM_SCHEDULER',
        occurredAt: input.now,
      });
      created = true;
    });
    return { eventId, created };
  }

  async listDueEvents(eventType, now) {
    const snapshot = await this.firestore.collection(EVENT_COLLECTION)
      .where('eventType', '==', eventType)
      .where('status', '==', 'PENDING')
      .where('nextAttemptAt', '<=', now)
      .orderBy('nextAttemptAt', 'asc')
      .limit(MAX_DUE_EVENTS).get();
    return snapshot.docs.map((document) => ({ ...document.data(), eventId: document.id }));
  }

  async claimEvent(input) {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(input.eventId);
    let result = null;
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const event = snapshot.data();
      const nextAttemptAt = toDate(event?.nextAttemptAt);
      const leaseUntil = toDate(event?.deliveryLeaseUntil);
      if (!snapshot.exists || event.eventId !== input.eventId || event.eventType !== input.eventType ||
          event.status !== 'PENDING' || !nextAttemptAt || nextAttemptAt > input.now ||
          (leaseUntil && leaseUntil > input.now)) return;
      const attemptCount = Number.isSafeInteger(event.attemptCount) ? event.attemptCount + 1 : 1;
      transaction.update(eventRef, {
        deliveryLeaseId: input.leaseId,
        deliveryLeaseUntil: new Date(input.now.getTime() + DELIVERY_LEASE_MS),
        attemptCount,
        lastAttemptAt: input.now,
      });
      result = { ...event, attemptCount, deliveryLeaseId: input.leaseId };
    });
    return result;
  }

  async resolveDeliveryTargets(event, now) {
    const campaignRef = this.firestore.collection('task_campaigns').doc(event.campaignId);
    const policyRef = this.firestore.collection(POLICY_COLLECTION).doc(event.policyDocumentId);
    const communityRef = this.firestore.collection('rt_communities').doc(event.rtId);
    const [campaignSnapshot, policySnapshot, communitySnapshot] = await Promise.all([
      campaignRef.get(), policyRef.get(), communityRef.get(),
    ]);
    const policy = readPolicy(policySnapshot, event.policyDocumentId, event.rtId, event.policyFingerprint);
    if (!policy || !validCampaignForPolicy(
      campaignSnapshot, event.campaignId, policy, event.policyFingerprint, now, communitySnapshot,
    ) || event.policyVersion !== policy.version) return { valid: false, targets: [] };

    if (event.recipientKind === 'RESIDENT') {
      if (!HASH_PATTERN.test(event.recipientHash || '') ||
          !policy.reminderWindows.some((window) => window.windowId === event.windowId &&
            window.cohort === event.cohort)) return { valid: false, targets: [] };
      const window = policy.reminderWindows.find((item) => item.windowId === event.windowId);
      const campaign = campaignSnapshot.data();
      const dueAt = new Date(toDate(campaign.deadline).getTime() -
        window.minutesBeforeDeadline * 60_000);
      if (now < dueAt || now >= toDate(campaign.deadline)) return { valid: false, targets: [] };
      const tokenSnapshot = await this.firestore.collection(RESIDENT_TOKEN_COLLECTION)
        .where('rtId', '==', event.rtId)
        .where('recipientHash', '==', event.recipientHash)
        .where('active', '==', true).limit(20).get();
      const targets = [];
      for (const tokenDoc of tokenSnapshot.docs) {
        const tokenRecord = tokenDoc.data();
        if (tokenRecord.rtId !== event.rtId || typeof tokenRecord.residentId !== 'string' ||
            tokenRecord.recipientHash !== event.recipientHash ||
            typeof tokenRecord.sessionIdHash !== 'string' || typeof tokenRecord.token !== 'string') continue;
        const sessionRef = this.firestore.collection('resident_sessions').doc(tokenRecord.sessionIdHash);
        const residentRef = this.firestore.collection('resident_profiles').doc(tokenRecord.residentId);
        const responseId = responseDocumentId(event.rtId, event.campaignId, tokenRecord.residentId);
        const responseRef = this.firestore.collection('task_responses').doc(responseId);
        const [sessionSnapshot, residentSnapshot, responseSnapshot] = await Promise.all([
          sessionRef.get(), residentRef.get(), responseRef.get(),
        ]);
        const session = sessionSnapshot.data();
        const resident = residentSnapshot.data();
        if (!sessionSnapshot.exists || session.active !== true || session.rtId !== event.rtId ||
            session.residentId !== tokenRecord.residentId || !toDate(session.expiresAt) ||
            toDate(session.expiresAt) <= now || !residentSnapshot.exists ||
            resident.rtId !== event.rtId || resident.deletionPending === true ||
            residentNotificationRecipientHash(event.rtId, tokenRecord.residentId) !== event.recipientHash) continue;
        const response = responseFor(responseSnapshot, responseId, event.campaignId,
          event.rtId, tokenRecord.residentId);
        if (response === undefined || !cohortMatches(event.cohort, response)) continue;
        targets.push({ token: tokenRecord.token, tokenId: tokenDoc.id, tokenKind: 'RESIDENT' });
      }
      return { valid: tokenSnapshot.size === 0 || targets.length > 0, targets };
    }

    if (event.recipientKind !== 'PENDAMPING_RT' ||
        event.recipientHash !== pendampingRecipientHash(event.rtId) ||
        !policy.escalation.enabled || policy.escalation.windowId !== event.windowId ||
        policy.escalation.cohort !== event.cohort ||
        policy.escalation.minimumCohortSize !== event.minimumCohortSize) {
      return { valid: false, targets: [] };
    }
    const campaign = campaignSnapshot.data();
    const escalationDue = new Date(toDate(campaign.deadline).getTime() -
      policy.escalation.minutesBeforeDeadline * 60_000);
    if (now < escalationDue || now >= toDate(campaign.deadline)) return { valid: false, targets: [] };
    const residents = await this.listResidentStates(event.rtId, event.campaignId);
    const eligible = residents.filter((resident) => resident.valid &&
      cohortMatches(policy.escalation.cohort, resident.response));
    if (eligible.length < policy.escalation.minimumCohortSize) return { valid: false, targets: [] };
    const tokenSnapshot = await this.firestore.collection(OPERATOR_TOKEN_COLLECTION)
      .where('rtId', '==', event.rtId)
      .where('role', '==', 'PENDAMPING_RT')
      .where('active', '==', true).limit(100).get();
    const candidates = tokenSnapshot.docs.map((document) => ({ id: document.id, ...document.data() }))
      .filter((token) => token.rtId === event.rtId && token.role === 'PENDAMPING_RT' &&
        typeof token.operatorUid === 'string' && typeof token.token === 'string');
    const operatorSnapshots = candidates.length === 0 ? [] : await this.firestore.getAll(
      ...candidates.map((candidate) => this.firestore.collection('operators').doc(candidate.operatorUid)),
    );
    const operatorByUid = new Map(operatorSnapshots.map((snapshot) => [snapshot.id, snapshot.data()]));
    const targets = candidates.filter((candidate) => {
      const operator = operatorByUid.get(candidate.operatorUid);
      return operator?.active === true && operator.role === 'PENDAMPING_RT' &&
        operator.rtId === event.rtId;
    }).map((candidate) => ({
      token: candidate.token,
      tokenId: candidate.id,
      tokenKind: 'OPERATOR',
    }));
    return { valid: true, targets };
  }

  async markEventSent(input) {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(input.eventId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const event = snapshot.data();
      if (!snapshot.exists || event.eventId !== input.eventId ||
          event.deliveryLeaseId !== input.leaseId || event.status !== 'PENDING') return;
      transaction.update(eventRef, {
        status: 'SENT',
        sentAt: input.now,
        deliveryLeaseId: FieldValue.delete(),
        deliveryLeaseUntil: FieldValue.delete(),
        lastErrorCode: FieldValue.delete(),
      });
    });
  }

  async markEventSkipped(input) {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(input.eventId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const event = snapshot.data();
      if (!snapshot.exists || event.eventId !== input.eventId ||
          event.deliveryLeaseId !== input.leaseId || event.status !== 'PENDING') return;
      transaction.update(eventRef, {
        status: 'SKIPPED',
        skipReason: input.reason,
        completedAt: input.now,
        deliveryLeaseId: FieldValue.delete(),
        deliveryLeaseUntil: FieldValue.delete(),
      });
    });
  }

  async markEventAttemptFailed(input) {
    const eventRef = this.firestore.collection(EVENT_COLLECTION).doc(input.eventId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(eventRef);
      const event = snapshot.data();
      if (!snapshot.exists || event.eventId !== input.eventId ||
          event.deliveryLeaseId !== input.leaseId || event.status !== 'PENDING') return;
      const attemptCount = Number.isSafeInteger(event.attemptCount) ? event.attemptCount : 1;
      const delaySeconds = event.deliveryRetrySeconds?.[attemptCount - 1];
      transaction.update(eventRef, {
        status: Number.isSafeInteger(delaySeconds) ? 'PENDING' : 'FAILED',
        ...(Number.isSafeInteger(delaySeconds) ? {
          nextAttemptAt: new Date(input.now.getTime() + delaySeconds * 1000),
        } : { completedAt: input.now }),
        lastErrorCode: input.errorCode,
        deliveryLeaseId: FieldValue.delete(),
        deliveryLeaseUntil: FieldValue.delete(),
      });
    });
  }

  async disableToken(tokenKind, tokenId, now) {
    const collection = tokenKind === 'RESIDENT' ? RESIDENT_TOKEN_COLLECTION : OPERATOR_TOKEN_COLLECTION;
    const tokenRef = this.firestore.collection(collection).doc(tokenId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(tokenRef);
      if (!snapshot.exists || snapshot.data()?.active !== true) return;
      transaction.update(tokenRef, { active: false, disabledAt: now });
    });
  }

  async registerResidentToken(input) {
    const sessionRef = this.firestore.collection('resident_sessions').doc(input.sessionIdHash);
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    const communityRef = this.firestore.collection('rt_communities').doc(input.rtId);
    const tokenRef = this.firestore.collection(RESIDENT_TOKEN_COLLECTION).doc(input.tokenId);
    await this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, communitySnapshot, tokenSnapshot] =
        await Promise.all([
          transaction.get(sessionRef), transaction.get(residentRef),
          transaction.get(communityRef), transaction.get(tokenRef),
        ]);
      const session = sessionSnapshot.data();
      const resident = residentSnapshot.data();
      if (!sessionSnapshot.exists || session.active !== true || session.rtId !== input.rtId ||
          session.residentId !== input.residentId || !toDate(session.expiresAt) ||
          toDate(session.expiresAt) <= input.now || !residentSnapshot.exists ||
          resident.rtId !== input.rtId || resident.deletionPending === true ||
          !communitySnapshot.exists || communitySnapshot.id !== input.rtId) deny();
      const old = tokenSnapshot.data();
      if (tokenSnapshot.exists && (old?.residentId !== input.residentId || old?.rtId !== input.rtId)) {
        deny();
      }
      transaction.set(tokenRef, {
        tokenId: input.tokenId,
        token: input.token,
        platform: input.platform,
        rtId: input.rtId,
        residentId: input.residentId,
        recipientHash: residentNotificationRecipientHash(input.rtId, input.residentId),
        sessionIdHash: input.sessionIdHash,
        active: true,
        createdAt: old?.createdAt ?? input.now,
        updatedAt: input.now,
      });
    });
  }

  async unregisterResidentToken(input) {
    const sessionRef = this.firestore.collection('resident_sessions').doc(input.sessionIdHash);
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    const tokenRef = this.firestore.collection(RESIDENT_TOKEN_COLLECTION).doc(input.tokenId);
    await this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, tokenSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(tokenRef),
      ]);
      const session = sessionSnapshot.data();
      const resident = residentSnapshot.data();
      if (!sessionSnapshot.exists || session.active !== true || session.residentId !== input.residentId ||
          session.rtId !== input.rtId || !toDate(session.expiresAt) ||
          toDate(session.expiresAt) <= input.now || !residentSnapshot.exists || resident.rtId !== input.rtId) deny();
      if (tokenSnapshot.exists) {
        const token = tokenSnapshot.data();
        if (token.residentId !== input.residentId || token.rtId !== input.rtId) deny();
        transaction.delete(tokenRef);
      }
    });
  }

  async registerOperatorToken(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const tokenRef = this.firestore.collection(OPERATOR_TOKEN_COLLECTION).doc(input.tokenId);
    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, tokenSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(tokenRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (operator.role !== 'PENDAMPING_RT') deny();
      const old = tokenSnapshot.data();
      if (tokenSnapshot.exists && (old?.operatorUid !== input.operatorUid ||
          old?.rtId !== operator.rtId)) deny();
      transaction.set(tokenRef, {
        tokenId: input.tokenId,
        token: input.token,
        platform: input.platform,
        rtId: operator.rtId,
        role: operator.role,
        operatorUid: input.operatorUid,
        active: true,
        createdAt: old?.createdAt ?? input.now,
        updatedAt: input.now,
      });
    });
  }

  async unregisterOperatorToken(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const tokenRef = this.firestore.collection(OPERATOR_TOKEN_COLLECTION).doc(input.tokenId);
    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, tokenSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(tokenRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (operator.role !== 'PENDAMPING_RT') deny();
      if (tokenSnapshot.exists) {
        const token = tokenSnapshot.data();
        if (token.operatorUid !== input.operatorUid || token.rtId !== operator.rtId) deny();
        transaction.delete(tokenRef);
      }
    });
  }

  async listAuditEvents(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    let items = [];
    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, campaignSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(campaignRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (!campaignSnapshot.exists || campaignSnapshot.data()?.rtId !== operator.rtId ||
          campaignSnapshot.data()?.campaignId !== input.campaignId) deny();
      const events = await transaction.get(this.firestore.collection(AUDIT_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('campaignId', '==', input.campaignId)
        .orderBy('occurredAt', 'desc').limit(50));
      items = events.docs.map((snapshot) => {
        const event = snapshot.data();
        if (event.eventId !== snapshot.id || event.rtId !== operator.rtId ||
            event.campaignId !== input.campaignId ||
            !['TASK_REMINDER', 'TASK_ESCALATION'].includes(event.eventType) ||
            typeof event.windowId !== 'string' || !toDate(event.occurredAt)) return null;
        return {
          eventType: event.eventType,
          windowId: event.windowId,
          occurredAt: toDate(event.occurredAt).toISOString(),
        };
      }).filter(Boolean);
    });
    return items;
  }
}

module.exports = {
  AUDIT_COLLECTION,
  EVENT_COLLECTION,
  FirestoreTaskNotificationRepository,
  TaskNotificationError,
  validateToken,
};
