const { FieldValue } = require('firebase-admin/firestore');
const { OPERATOR_ROLES, TaskCampaignError, asDate } = require('./task_campaign_service');
const { responseDocumentId } = require('./task_response_service');

const EVIDENCE_COLLECTION = 'task_evidence';
const SESSION_COLLECTION = 'resident_sessions';
const RESIDENT_COLLECTION = 'resident_profiles';
const COMMUNITY_COLLECTION = 'rt_communities';
const CAMPAIGN_COLLECTION = 'task_campaigns';
const RESPONSE_COLLECTION = 'task_responses';

function fail(code, message = 'Bukti tugas tidak dapat diproses.') {
  return new TaskCampaignError(code, message);
}

function deny() {
  return fail('permission-denied');
}

function requireResidentSession(sessionSnapshot, residentSnapshot, communitySnapshot, input) {
  const session = sessionSnapshot.data();
  const resident = residentSnapshot.data();
  const expiresAt = asDate(session?.expiresAt);
  if (!sessionSnapshot.exists || session?.active !== true || !expiresAt ||
      expiresAt <= input.now || session.residentId !== input.residentId ||
      session.rtId !== input.rtId || !residentSnapshot.exists ||
      resident?.rtId !== input.rtId || typeof resident?.nickname !== 'string' ||
      !resident.nickname.trim() || !communitySnapshot.exists || communitySnapshot.id !== input.rtId) {
    throw deny();
  }
}

function requireActiveJoinedTask(campaignSnapshot, responseSnapshot, input, responseId) {
  const campaign = campaignSnapshot.data();
  const response = responseSnapshot.data();
  if (!campaignSnapshot.exists || campaignSnapshot.id !== input.taskId ||
      campaign?.campaignId !== input.taskId || campaign.rtId !== input.rtId ||
      campaign.status !== 'ACTIVE' || !responseSnapshot.exists ||
      responseSnapshot.id !== responseId || response?.responseId !== responseId ||
      response.taskId !== input.taskId || response.rtId !== input.rtId ||
      response.residentId !== input.residentId || response.participationState !== 'JOINED' ||
      response.completionState !== 'NOT_SUBMITTED') {
    throw fail('failed-precondition', 'Bukti hanya dapat ditambahkan pada tugas yang diikuti.');
  }
}

function validateEvidenceRecord(snapshot, input) {
  const record = snapshot.data();
  if (!snapshot.exists || snapshot.id !== input.evidenceId ||
      record?.evidenceId !== input.evidenceId || record.rtId !== input.rtId ||
      record.taskId !== input.taskId || record.residentScopeHash !== input.residentScopeHash ||
      record.responseId !== input.responseId || record.commandHash !== input.commandHash ||
      record.contentHash !== input.contentHash || record.storagePath !== input.storagePath ||
      !['UPLOADING', 'READY'].includes(record.status)) {
    throw fail('failed-precondition', 'Permintaan unggah bukti sudah digunakan.');
  }
  const expiresAt = asDate(record.expiresAt);
  const createdAt = asDate(record.createdAt);
  if (!expiresAt || !createdAt || expiresAt <= createdAt) {
    throw fail('failed-precondition', 'Masa simpan bukti tidak valid.');
  }
  if (expiresAt <= input.now) {
    throw fail('failed-precondition', 'Masa simpan bukti sudah berakhir.');
  }
  return record;
}

class FirestoreTaskEvidenceRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async getForOperator(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, evidenceSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(evidenceRef),
      ]);
      const operator = operatorSnapshot.data();
      const evidence = evidenceSnapshot.data();
      const expiresAt = asDate(evidence?.expiresAt);
      if (!operatorSnapshot.exists || operator?.active !== true ||
          !OPERATOR_ROLES.has(operator.role) || typeof operator.rtId !== 'string' ||
          !evidenceSnapshot.exists || evidence?.evidenceId !== input.evidenceId ||
          evidence.rtId !== operator.rtId || evidence.status !== 'READY' ||
          !expiresAt || expiresAt <= input.now || typeof evidence.storagePath !== 'string') {
        throw deny();
      }
      const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(evidence.responseId);
      const responseSnapshot = await transaction.get(responseRef);
      const response = responseSnapshot.data();
      if (!responseSnapshot.exists || response?.responseId !== evidence.responseId ||
          response.evidenceId !== input.evidenceId || response.rtId !== operator.rtId ||
          response.taskId !== evidence.taskId ||
          response.completionState !== 'PENDING_RT_VERIFICATION') {
        throw deny();
      }
      return { evidenceId: input.evidenceId, storagePath: evidence.storagePath };
    });
  }

  async reserveUpload(input) {
    const responseId = responseDocumentId(input.rtId, input.taskId, input.residentId);
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const communityRef = this.firestore.collection(COMMUNITY_COLLECTION).doc(input.rtId);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(input.taskId);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    const transactionInput = { ...input, responseId };

    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, communitySnapshot, campaignSnapshot,
        responseSnapshot, evidenceSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(communityRef),
        transaction.get(campaignRef), transaction.get(responseRef), transaction.get(evidenceRef),
      ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, communitySnapshot, transactionInput);
      requireActiveJoinedTask(campaignSnapshot, responseSnapshot, transactionInput, responseId);
      if (evidenceSnapshot.exists) {
        const record = validateEvidenceRecord(evidenceSnapshot, transactionInput);
        return record;
      }

      const record = {
        evidenceId: input.evidenceId,
        rtId: input.rtId,
        taskId: input.taskId,
        responseId,
        residentScopeHash: input.residentScopeHash,
        commandHash: input.commandHash,
        contentHash: input.contentHash,
        storagePath: input.storagePath,
        status: 'UPLOADING',
        createdAt: input.now,
        expiresAt: input.expiresAt,
        deletionCommandHash: null,
        deleteAttemptCount: 0,
      };
      transaction.create(evidenceRef, record);
      return record;
    });
  }

  async markReady(input) {
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(evidenceRef);
      const record = snapshot.data();
      if (!snapshot.exists || record?.evidenceId !== input.evidenceId || record.rtId !== input.rtId ||
          record.residentScopeHash !== input.residentScopeHash || record.contentHash !== input.contentHash) {
        throw fail('failed-precondition', 'Bukti unggah tidak konsisten.');
      }
      if (record.status === 'READY') return record;
      if (record.status !== 'UPLOADING') {
        throw fail('failed-precondition', 'Bukti tidak dapat diaktifkan kembali.');
      }
      transaction.update(evidenceRef, { status: 'READY', uploadedAt: input.now });
      return { ...record, status: 'READY', uploadedAt: input.now };
    });
  }

  async requestResidentDeletion(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const communityRef = this.firestore.collection(COMMUNITY_COLLECTION).doc(input.rtId);
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, communitySnapshot, evidenceSnapshot] =
        await Promise.all([
          transaction.get(sessionRef), transaction.get(residentRef),
          transaction.get(communityRef), transaction.get(evidenceRef),
        ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, communitySnapshot, input);
      const record = evidenceSnapshot.data();
      if (!evidenceSnapshot.exists || record?.evidenceId !== input.evidenceId ||
          record.rtId !== input.rtId || record.residentScopeHash !== input.residentScopeHash) {
        throw deny();
      }
      if (record.status === 'DELETED') return record;
      if (record.deletionCommandHash && record.deletionCommandHash !== input.commandHash) {
        throw fail('failed-precondition', 'Penghapusan bukti sedang diproses.');
      }
      if (!['UPLOADING', 'READY', 'DELETE_PENDING'].includes(record.status)) {
        throw fail('failed-precondition');
      }
      if (record.status !== 'DELETE_PENDING' || !record.deletionCommandHash) {
        transaction.update(evidenceRef, {
          status: 'DELETE_PENDING',
          deletionCommandHash: input.commandHash,
          deleteRequestedAt: input.now,
        });
      }
      return { ...record, status: 'DELETE_PENDING', deletionCommandHash: input.commandHash };
    });
  }

  async listDueEvidence(input) {
    const snapshot = await this.firestore.collection(EVIDENCE_COLLECTION)
      .where('expiresAt', '<=', input.now)
      .limit(input.limit)
      .get();
    return snapshot.docs
      .map((doc) => ({ ...doc.data(), evidenceId: doc.id }))
      .filter((record) => record.status !== 'DELETED');
  }

  async beginExpiredDeletion(input) {
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(evidenceRef);
      const record = snapshot.data();
      const expiresAt = asDate(record?.expiresAt);
      if (!snapshot.exists || record?.evidenceId !== input.evidenceId || !expiresAt ||
          expiresAt > input.now || record.status === 'DELETED') return null;
      if (typeof record.storagePath !== 'string' || !record.storagePath) {
        throw fail('failed-precondition', 'Lokasi penyimpanan bukti tidak valid.');
      }
      if (record.status !== 'DELETE_PENDING') {
        transaction.update(evidenceRef, { status: 'DELETE_PENDING', deleteRequestedAt: input.now });
      }
      return { ...record, status: 'DELETE_PENDING' };
    });
  }

  async markDeleted(input) {
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const evidenceSnapshot = await transaction.get(evidenceRef);
      const record = evidenceSnapshot.data();
      if (!evidenceSnapshot.exists || record?.evidenceId !== input.evidenceId) return;
      if (record.status === 'DELETED') return;
      const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(record.responseId);
      const responseSnapshot = await transaction.get(responseRef);
      transaction.update(evidenceRef, {
        status: 'DELETED',
        deletedAt: input.now,
        storagePath: FieldValue.delete(),
        contentHash: FieldValue.delete(),
        responseId: FieldValue.delete(),
        commandHash: FieldValue.delete(),
        deletionCommandHash: FieldValue.delete(),
        createdAt: FieldValue.delete(),
        expiresAt: FieldValue.delete(),
        uploadedAt: FieldValue.delete(),
        deleteRequestedAt: FieldValue.delete(),
        lastDeleteAttemptAt: FieldValue.delete(),
        deleteAttemptCount: FieldValue.delete(),
      });
      if (responseSnapshot.exists && responseSnapshot.data()?.evidenceId === input.evidenceId) {
        transaction.update(responseRef, {
          evidenceId: FieldValue.delete(),
          updatedAt: input.now,
        });
      }
    });
  }

  async markDeleteFailed(input) {
    const evidenceRef = this.firestore.collection(EVIDENCE_COLLECTION).doc(input.evidenceId);
    return this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(evidenceRef);
      const record = snapshot.data();
      if (!snapshot.exists || record?.evidenceId !== input.evidenceId || record.status === 'DELETED') return;
      transaction.update(evidenceRef, {
        status: 'DELETE_PENDING',
        lastDeleteAttemptAt: input.now,
        deleteAttemptCount: (Number.isSafeInteger(record.deleteAttemptCount) ? record.deleteAttemptCount : 0) + 1,
      });
    });
  }
}

module.exports = {
  EVIDENCE_COLLECTION,
  FirestoreTaskEvidenceRepository,
  requireActiveJoinedTask,
  requireResidentSession,
};
