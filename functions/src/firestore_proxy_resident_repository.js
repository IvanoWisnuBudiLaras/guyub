const { OPERATOR_ROLES, asDate } = require('./task_campaign_service');
const { ProxyResidentError } = require('./proxy_resident_service');
const { responseDocumentId } = require('./task_response_service');

const OPERATOR_COLLECTION = 'operators';
const RESIDENT_COLLECTION = 'resident_profiles';
const CAMPAIGN_COLLECTION = 'task_campaigns';
const RESPONSE_COLLECTION = 'task_responses';
const PROXY_AUDIT_COLLECTION = 'proxy_status_audit_events';
const MAX_PROXY_RESIDENTS = 200;

function fail(code, message = 'Akses warga tidak valid.') {
  return new ProxyResidentError(code, message);
}
function deny() { throw fail('permission-denied'); }
function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true || !OPERATOR_ROLES.has(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) deny();
  return { rtId: data.rtId.trim(), role: data.role };
}
function requireProxyResident(snapshot, residentId, rtId) {
  const resident = snapshot.data();
  if (!snapshot.exists || resident?.residentId !== residentId || resident.rtId !== rtId ||
      resident.createdBy !== 'proxy' || typeof resident.nickname !== 'string' ||
      typeof resident.needsAssistance !== 'boolean') deny();
  return resident;
}
function auditMatches(audit, { auditId, action, input, operator }) {
  return audit?.auditId === auditId && audit.action === action &&
    audit.rtId === operator.rtId && audit.actorUid === input.operatorUid &&
    audit.targetResidentId === input.residentId &&
    audit.commandHash === (input.requestHash ?? input.commandHash) &&
    audit.residentConsentConfirmed === true && asDate(audit.occurredAt) !== null;
}
function publicProfile(snapshot) {
  const record = snapshot.data();
  if (record.residentId !== snapshot.id || record.createdBy !== 'proxy' ||
      typeof record.nickname !== 'string' || typeof record.needsAssistance !== 'boolean' ||
      !asDate(record.createdAt)) return null;
  return {
    residentId: record.residentId,
    rtId: record.rtId,
    nickname: record.nickname,
    houseNumber: record.houseNumber ?? null,
    needsAssistance: record.needsAssistance,
    createdAt: record.createdAt,
  };
}
function responseView(snapshot) {
  const response = snapshot.data();
  return {
    responseId: response.responseId,
    taskId: response.taskId,
    rtId: response.rtId,
    residentId: response.residentId,
    participationState: response.participationState,
    completionState: response.completionState,
    completionNote: response.completionNote ?? null,
    completionSubmittedAt: response.completionSubmittedAt ?? null,
    verifiedAt: response.verifiedAt ?? null,
    evidenceId: response.evidenceId ?? null,
  };
}
function proxyStatusAuditMatches(audit, input, operator, responseId, action) {
  return audit?.auditId === `${responseId}_${input.commandHash}` &&
    audit.action === action && audit.rtId === operator.rtId &&
    audit.taskId === input.taskId && audit.responseId === responseId &&
    audit.targetResidentId === input.residentId && audit.actorUid === input.operatorUid &&
    audit.commandHash === input.commandHash &&
    audit.participationState === input.participationState &&
    audit.completionReported === input.completionReported &&
    audit.residentConsentConfirmed === true && asDate(audit.occurredAt) !== null;
}

class FirestoreProxyResidentRepository {
  constructor(firestore) { this.firestore = firestore; }

  async getOperatorRtId(operatorUid) {
    const snapshot = await this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid).get();
    return requireOperator(snapshot).rtId;
  }

  async createProxyResident(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const auditId = `${input.residentId}_created`;
    const auditRef = this.firestore.collection(PROXY_AUDIT_COLLECTION).doc(auditId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, residentSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(residentRef), transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (operator.rtId !== input.expectedRtId) deny();
      if (residentSnapshot.exists) {
        const existing = residentSnapshot.data();
        const audit = auditSnapshot.data();
        if (existing.rtId === operator.rtId && existing.createdBy === 'proxy' &&
            existing.residentId === input.residentId && existing.nickname === input.nickname &&
            (existing.houseNumber ?? null) === (input.houseNumber ?? null) &&
            existing.needsAssistance === input.needsAssistance &&
            auditMatches(audit, { auditId, action: 'PROXY_RESIDENT_CREATED', input, operator })) {
          result = existing;
          return;
        }
        throw fail('already-exists', 'ID permintaan sudah digunakan.');
      }
      if (auditSnapshot.exists) throw fail('failed-precondition', 'Riwayat warga tidak konsisten.');
      const record = {
        residentId: input.residentId,
        rtId: operator.rtId,
        nickname: input.nickname,
        ...(input.houseNumber == null ? {} : { houseNumber: input.houseNumber }),
        needsAssistance: input.needsAssistance,
        createdBy: 'proxy',
        createdAt: input.now,
        updatedAt: input.now,
      };
      transaction.create(residentRef, record);
      transaction.create(auditRef, {
        auditId,
        action: 'PROXY_RESIDENT_CREATED',
        rtId: operator.rtId,
        targetResidentId: input.residentId,
        actorUid: input.operatorUid,
        commandHash: input.requestHash,
        residentConsentConfirmed: true,
        needsAssistance: input.needsAssistance,
        occurredAt: input.now,
      });
      result = record;
    });
    return result;
  }

  async listProxyResidents({ operatorUid }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    return this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      const query = this.firestore.collection(RESIDENT_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('createdBy', '==', 'proxy')
        .orderBy('createdAt', 'asc')
        .limit(MAX_PROXY_RESIDENTS + 1);
      const snapshot = await transaction.get(query);
      const items = snapshot.docs.slice(0, MAX_PROXY_RESIDENTS).map(publicProfile)
        .filter((item) => item !== null && item.rtId === operator.rtId)
        .map(({ rtId: _rtId, ...item }) => item);
      return { items, isPartial: snapshot.size > MAX_PROXY_RESIDENTS };
    });
  }

  async getProxyTaskStatus(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(input.taskId);
    const responseId = responseDocumentId(input.rtId, input.taskId, input.residentId);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);

    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, residentSnapshot, campaignSnapshot, responseSnapshot] =
        await Promise.all([
          transaction.get(operatorRef), transaction.get(residentRef),
          transaction.get(campaignRef), transaction.get(responseRef),
        ]);
      const operator = requireOperator(operatorSnapshot);
      const resident = requireProxyResident(residentSnapshot, input.residentId, operator.rtId);
      const campaign = campaignSnapshot.data();
      if (operator.rtId !== input.rtId || !campaignSnapshot.exists ||
          campaign.campaignId !== input.taskId || campaign.rtId !== operator.rtId ||
          campaign.status !== 'ACTIVE' || resident.rtId !== campaign.rtId) deny();
      if (!responseSnapshot.exists) {
        return {
          taskId: input.taskId,
          participationState: 'UNRESPONDED',
          completionState: 'NOT_SUBMITTED',
        };
      }
      const response = responseSnapshot.data();
      if (response.responseId !== responseId || response.taskId !== input.taskId ||
          response.rtId !== operator.rtId || response.residentId !== input.residentId ||
          response.proxyRecordedBy !== true) deny();
      return responseView(responseSnapshot);
    });
  }

  async updateProxyAssistance(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const auditId = `${input.residentId}_assistance_${input.commandHash}`;
    const auditRef = this.firestore.collection(PROXY_AUDIT_COLLECTION).doc(auditId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, residentSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(residentRef), transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      const resident = requireProxyResident(residentSnapshot, input.residentId, operator.rtId);
      const audit = auditSnapshot.data();
      if (auditSnapshot.exists) {
        if (auditMatches(audit, {
          auditId, action: 'PROXY_ASSISTANCE_STATUS_UPDATED', input, operator,
        }) && audit.needsAssistance === input.needsAssistance) {
          result = resident;
          return;
        }
        throw fail('already-exists', 'ID permintaan sudah digunakan.');
      }
      if (resident.needsAssistance === input.needsAssistance) {
        result = resident;
        return;
      }
      transaction.update(residentRef, {
        needsAssistance: input.needsAssistance,
        updatedAt: input.now,
      });
      transaction.create(auditRef, {
        auditId,
        action: 'PROXY_ASSISTANCE_STATUS_UPDATED',
        rtId: operator.rtId,
        targetResidentId: input.residentId,
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        needsAssistance: input.needsAssistance,
        residentConsentConfirmed: true,
        occurredAt: input.now,
      });
      result = { ...resident, needsAssistance: input.needsAssistance };
    });
    return result;
  }

  async updateProxyTaskStatus(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(input.taskId);
    const responseId = responseDocumentId(input.rtId, input.taskId, input.residentId);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);
    const action = input.completionReported
      ? 'PROXY_COMPLETION_REPORTED' : 'PROXY_PARTICIPATION_RECORDED';
    const auditId = `${responseId}_${input.commandHash}`;
    const auditRef = this.firestore.collection(PROXY_AUDIT_COLLECTION).doc(auditId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, residentSnapshot, campaignSnapshot, responseSnapshot, auditSnapshot] =
        await Promise.all([
          transaction.get(operatorRef), transaction.get(residentRef),
          transaction.get(campaignRef), transaction.get(responseRef), transaction.get(auditRef),
        ]);
      const operator = requireOperator(operatorSnapshot);
      const resident = requireProxyResident(residentSnapshot, input.residentId, operator.rtId);
      const campaign = campaignSnapshot.data();
      if (!campaignSnapshot.exists || campaign.campaignId !== input.taskId ||
          campaign.rtId !== operator.rtId || campaign.status !== 'ACTIVE' ||
          input.rtId !== operator.rtId || resident.rtId !== campaign.rtId) deny();

      if (responseSnapshot.exists) {
        const current = responseSnapshot.data();
        if (current.responseId !== responseId || current.taskId !== input.taskId ||
            current.rtId !== operator.rtId || current.residentId !== input.residentId ||
            current.proxyRecordedBy !== true) deny();
        if (auditSnapshot.exists) {
          if (proxyStatusAuditMatches(
            auditSnapshot.data(), input, operator, responseId, action,
          )) {
            result = responseSnapshot;
            return;
          }
          throw fail('already-exists', 'ID permintaan sudah digunakan.');
        }
        if (current.participationState !== input.participationState) {
          throw fail('failed-precondition', 'Pilihan sukarela yang tercatat tidak dapat diubah.');
        }
        if (input.completionReported && current.completionState === 'NOT_SUBMITTED') {
          if (auditSnapshot.exists) throw fail('failed-precondition', 'Riwayat status tidak konsisten.');
          transaction.update(responseRef, {
            completionState: 'PENDING_RT_VERIFICATION',
            completionCommandHash: input.commandHash,
            completionSubmittedAt: input.now,
            updatedAt: input.now,
          });
          transaction.create(auditRef, {
            auditId, action, rtId: operator.rtId, taskId: input.taskId,
            responseId, targetResidentId: input.residentId, actorUid: input.operatorUid,
            commandHash: input.commandHash, participationState: input.participationState,
            completionReported: true, residentConsentConfirmed: true, occurredAt: input.now,
          });
          result = { ...current, completionState: 'PENDING_RT_VERIFICATION' };
          return;
        }
        if (!input.completionReported || current.completionState !== 'NOT_SUBMITTED') {
          result = responseSnapshot;
          return;
        }
      }
      if (auditSnapshot.exists) throw fail('failed-precondition', 'Riwayat status tidak konsisten.');
      const record = {
        responseId,
        taskId: input.taskId,
        rtId: operator.rtId,
        residentId: input.residentId,
        participationState: input.participationState,
        participationCommandHash: input.commandHash,
        completionState: input.completionReported ? 'PENDING_RT_VERIFICATION' : 'NOT_SUBMITTED',
        completionNote: null,
        completionCommandHash: input.completionReported ? input.commandHash : null,
        completionSubmittedAt: input.completionReported ? input.now : null,
        verifiedAt: null,
        verifiedByOperatorUid: null,
        verificationCommandHash: null,
        proxyRecordedBy: true,
        createdAt: input.now,
        updatedAt: input.now,
      };
      transaction.create(responseRef, record);
      transaction.create(auditRef, {
        auditId, action, rtId: operator.rtId, taskId: input.taskId,
        responseId, targetResidentId: input.residentId, actorUid: input.operatorUid,
        commandHash: input.commandHash, participationState: input.participationState,
        completionReported: input.completionReported, residentConsentConfirmed: true,
        occurredAt: input.now,
      });
      result = record;
    });
    if (result && typeof result.data === 'function') return responseView(result);
    return result;
  }
}

module.exports = { FirestoreProxyResidentRepository };
