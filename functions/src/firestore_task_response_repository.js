const {
  OPERATOR_ROLES,
  TaskCampaignError,
  asDate,
} = require('./task_campaign_service');
const { responseDocumentId } = require('./task_response_service');

const RESPONSE_COLLECTION = 'task_responses';
const CAMPAIGN_COLLECTION = 'task_campaigns';
const OPERATOR_COLLECTION = 'operators';
const RESIDENT_COLLECTION = 'resident_profiles';
const SESSION_COLLECTION = 'resident_sessions';
const AUDIT_COLLECTION = 'task_audit_events';
const MAX_ACTIVE_TASKS = 200;
const MAX_PENDING_VERIFICATIONS = 100;
const MAX_RECAP_RESPONSES = 400;

function fail(code, message = 'Akses tugas tidak valid.') {
  return new TaskCampaignError(code, message);
}

function deny() {
  return fail('permission-denied');
}

function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true || !OPERATOR_ROLES.has(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) {
    throw deny();
  }
  return { rtId: data.rtId.trim(), role: data.role };
}

function requireResidentSession(sessionSnapshot, residentSnapshot, input) {
  const session = sessionSnapshot.data();
  const resident = residentSnapshot.data();
  const expiresAt = asDate(session?.expiresAt);
  if (!sessionSnapshot.exists || session?.active !== true || !expiresAt ||
      expiresAt <= input.now || session.residentId !== input.residentId ||
      session.rtId !== input.rtId || !residentSnapshot.exists ||
      resident?.rtId !== input.rtId || typeof resident?.nickname !== 'string') {
    throw deny();
  }
}

function requireCampaign(snapshot, taskId, rtId, { active = false } = {}) {
  const campaign = snapshot.data();
  if (!snapshot.exists || campaign?.campaignId !== taskId || campaign.rtId !== rtId ||
      (active && campaign.status !== 'ACTIVE')) {
    throw deny();
  }
  return campaign;
}

function requireResponseIdentity(snapshot, responseId, taskId, rtId, residentId) {
  const response = snapshot.data();
  if (snapshot.exists && (snapshot.id !== responseId || response?.responseId !== responseId ||
      response.taskId !== taskId || response.rtId !== rtId ||
      response.residentId !== residentId)) {
    throw fail('failed-precondition', 'Respons tugas tidak konsisten.');
  }
  return response;
}

function responseRecord(input, responseId) {
  return {
    responseId,
    taskId: input.taskId,
    rtId: input.rtId,
    residentId: input.residentId,
    participationState: input.choice,
    participationCommandHash: input.commandHash,
    completionState: 'NOT_SUBMITTED',
    completionNote: null,
    completionCommandHash: null,
    completionSubmittedAt: null,
    verifiedAt: null,
    verifiedByOperatorUid: null,
    verificationCommandHash: null,
    createdAt: input.now,
    updatedAt: input.now,
  };
}

function campaignView(snapshot) {
  const campaign = snapshot.data();
  return {
    campaignId: campaign.campaignId,
    rtId: campaign.rtId,
    templateSnapshot: campaign.templateSnapshot,
    deadline: campaign.deadline,
    locationReference: campaign.locationReference ?? null,
    additionalNote: campaign.additionalNote ?? null,
    status: campaign.status,
  };
}

function responseView(snapshot) {
  if (!snapshot.exists) return null;
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
  };
}

function assertOperatorTask(operator, campaign, response) {
  if (campaign.rtId !== operator.rtId || response.rtId !== operator.rtId) throw deny();
}

class FirestoreTaskResponseRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async listActiveTasks(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const activeTasks = this.firestore.collection(CAMPAIGN_COLLECTION)
      .where('rtId', '==', input.rtId)
      .where('status', '==', 'ACTIVE')
      .orderBy('deadline', 'asc')
      .limit(MAX_ACTIVE_TASKS + 1);

    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, tasksSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(activeTasks),
      ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, input);
      const taskDocs = tasksSnapshot.docs.slice(0, MAX_ACTIVE_TASKS);
      const responseSnapshots = await Promise.all(taskDocs.map((taskDoc) => {
        const campaign = taskDoc.data();
        const responseId = responseDocumentId(input.rtId, campaign.campaignId, input.residentId);
        return transaction.get(this.firestore.collection(RESPONSE_COLLECTION).doc(responseId));
      }));
      const items = taskDocs.map((taskSnapshot, index) => {
        const campaign = campaignView(taskSnapshot);
        const responseSnapshot = responseSnapshots[index];
        const response = responseView(responseSnapshot);
        if (taskSnapshot.id !== campaign.campaignId || campaign.rtId !== input.rtId ||
            campaign.status !== 'ACTIVE') {
          throw fail('failed-precondition', 'Data tugas tidak konsisten.');
        }
        if (response && (response.taskId !== campaign.campaignId ||
            response.rtId !== input.rtId || response.residentId !== input.residentId)) {
          throw fail('failed-precondition', 'Respons tugas tidak konsisten.');
        }
        return { campaign, response };
      }).sort((left, right) => {
        const leftDeadline = asDate(left.campaign.deadline)?.getTime() ?? 0;
        const rightDeadline = asDate(right.campaign.deadline)?.getTime() ?? 0;
        return leftDeadline - rightDeadline;
      });
      return { items, isPartial: tasksSnapshot.size > MAX_ACTIVE_TASKS };
    });
  }

  async recordParticipation(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(input.taskId);
    const responseId = responseDocumentId(input.rtId, input.taskId, input.residentId);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);

    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, campaignSnapshot, responseSnapshot] =
        await Promise.all([
          transaction.get(sessionRef), transaction.get(residentRef),
          transaction.get(campaignRef), transaction.get(responseRef),
        ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, input);
      const campaign = requireCampaign(campaignSnapshot, input.taskId, input.rtId, { active: true });
      if (campaign.campaignId !== input.taskId) throw deny();
      const existing = requireResponseIdentity(
        responseSnapshot, responseId, input.taskId, input.rtId, input.residentId,
      );
      if (responseSnapshot.exists) {
        if (existing.participationState === input.choice) return responseView(responseSnapshot);
        throw fail('failed-precondition', 'Pilihan tugas sudah tersimpan dan tidak dapat diubah.');
      }
      const record = responseRecord(input, responseId);
      transaction.create(responseRef, record);
      return {
        responseId,
        taskId: input.taskId,
        rtId: input.rtId,
        residentId: input.residentId,
        participationState: record.participationState,
        completionState: record.completionState,
        completionNote: null,
        completionSubmittedAt: null,
        verifiedAt: null,
      };
    });
  }

  async submitCompletion(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(input.taskId);
    const responseId = responseDocumentId(input.rtId, input.taskId, input.residentId);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);

    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, campaignSnapshot, responseSnapshot] =
        await Promise.all([
          transaction.get(sessionRef), transaction.get(residentRef),
          transaction.get(campaignRef), transaction.get(responseRef),
        ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, input);
      requireCampaign(campaignSnapshot, input.taskId, input.rtId, { active: true });
      if (!responseSnapshot.exists) {
        throw fail('failed-precondition', 'Pilih Ikut sebelum mengirim penyelesaian.');
      }
      const existing = requireResponseIdentity(
        responseSnapshot, responseId, input.taskId, input.rtId, input.residentId,
      );
      if (existing.participationState !== 'JOINED') {
        throw fail('failed-precondition', 'Penyelesaian hanya tersedia untuk peserta yang ikut.');
      }
      if (existing.completionState === 'PENDING_RT_VERIFICATION') {
        if (existing.completionCommandHash === input.commandHash &&
            (existing.completionNote ?? null) === input.completionNote) {
          return responseView(responseSnapshot);
        }
        throw fail('failed-precondition', 'Penyelesaian sedang menunggu verifikasi RT.');
      }
      if (existing.completionState !== 'NOT_SUBMITTED') {
        throw fail('failed-precondition', 'Status penyelesaian tidak dapat diubah.');
      }
      const updated = {
        completionState: 'PENDING_RT_VERIFICATION',
        completionNote: input.completionNote,
        completionCommandHash: input.commandHash,
        completionSubmittedAt: input.now,
        updatedAt: input.now,
      };
      transaction.update(responseRef, updated);
      return {
        ...responseView(responseSnapshot),
        completionState: updated.completionState,
        completionNote: updated.completionNote,
        completionSubmittedAt: updated.completionSubmittedAt,
      };
    });
  }

  async listPendingVerifications({ operatorUid }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    return this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      const pendingQuery = this.firestore.collection(RESPONSE_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('completionState', '==', 'PENDING_RT_VERIFICATION')
        .orderBy('completionSubmittedAt', 'asc')
        .limit(MAX_PENDING_VERIFICATIONS + 1);
      const pendingSnapshot = await transaction.get(pendingQuery);
      const responseDocs = pendingSnapshot.docs.slice(0, MAX_PENDING_VERIFICATIONS);
      const related = await Promise.all(responseDocs.map(async (responseSnapshot) => {
        const response = responseSnapshot.data();
        const [campaignSnapshot, residentSnapshot] = await Promise.all([
          transaction.get(this.firestore.collection(CAMPAIGN_COLLECTION).doc(response.taskId)),
          transaction.get(this.firestore.collection(RESIDENT_COLLECTION).doc(response.residentId)),
        ]);
        return { responseSnapshot, campaignSnapshot, residentSnapshot };
      }));
      const items = related.map(({ responseSnapshot, campaignSnapshot, residentSnapshot }) => {
        const response = responseSnapshot.data();
        if (!campaignSnapshot.exists || !residentSnapshot.exists) return null;
        const campaign = campaignSnapshot.data();
        const resident = residentSnapshot.data();
        if (campaign.rtId !== operator.rtId || response.rtId !== operator.rtId ||
            resident.rtId !== operator.rtId || typeof resident.nickname !== 'string' ||
            campaign.campaignId !== response.taskId ||
            response.responseId !== responseSnapshot.id ||
            responseDocumentId(response.rtId, response.taskId, response.residentId) !==
              responseSnapshot.id) {
          return null;
        }
        return {
          responseId: response.responseId,
          taskId: response.taskId,
          taskTitle: campaign.templateSnapshot?.title ?? '',
          nickname: resident.nickname,
          completionNote: response.completionNote ?? null,
          completionSubmittedAt: response.completionSubmittedAt ?? null,
        };
      }).filter((item) => item !== null).sort((left, right) => {
        const leftTime = asDate(left.completionSubmittedAt)?.getTime() ?? 0;
        const rightTime = asDate(right.completionSubmittedAt)?.getTime() ?? 0;
        return leftTime - rightTime;
      });
      return { items, isPartial: pendingSnapshot.size > MAX_PENDING_VERIFICATIONS };
    });
  }

  async verifyCompletion({ operatorUid, responseId, commandHash, now }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    const responseRef = this.firestore.collection(RESPONSE_COLLECTION).doc(responseId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(`${responseId}_verified`);

    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, responseSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(responseRef), transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      if (!responseSnapshot.exists) throw deny();
      const response = responseSnapshot.data();
      if (response.responseId !== responseId ||
          responseDocumentId(response.rtId, response.taskId, response.residentId) !== responseId ||
          response.rtId !== operator.rtId) {
        throw deny();
      }
      const campaignSnapshot = await transaction.get(
        this.firestore.collection(CAMPAIGN_COLLECTION).doc(response.taskId),
      );
      if (!campaignSnapshot.exists) throw deny();
      const campaign = campaignSnapshot.data();
      if (campaign.rtId !== operator.rtId || campaign.campaignId !== response.taskId) throw deny();
      if (response.completionState === 'VERIFIED_COMPLETE') {
        const audit = auditSnapshot.data();
        if (response.verificationCommandHash === commandHash &&
            response.verifiedByOperatorUid === operatorUid && auditSnapshot.exists &&
            audit?.action === 'TASK_COMPLETION_VERIFIED' && audit?.responseId === responseId &&
            audit?.taskId === response.taskId && audit?.rtId === operator.rtId &&
            audit?.actorUid === operatorUid && audit?.commandHash === commandHash) {
          return responseView(responseSnapshot);
        }
        throw fail('failed-precondition', 'Penyelesaian sudah diverifikasi.');
      }
      if (response.completionState !== 'PENDING_RT_VERIFICATION') {
        throw fail('failed-precondition', 'Penyelesaian belum menunggu verifikasi RT.');
      }
      if (auditSnapshot.exists) throw fail('failed-precondition', 'Catatan verifikasi tidak konsisten.');
      const audit = {
        auditId: `${responseId}_verified`,
        action: 'TASK_COMPLETION_VERIFIED',
        rtId: operator.rtId,
        taskId: response.taskId,
        responseId,
        actorUid: operatorUid,
        commandHash,
        occurredAt: now,
      };
      transaction.update(responseRef, {
        completionState: 'VERIFIED_COMPLETE',
        verifiedAt: now,
        verifiedByOperatorUid: operatorUid,
        verificationCommandHash: commandHash,
        updatedAt: now,
      });
      transaction.create(auditRef, audit);
      return {
        ...responseView(responseSnapshot),
        completionState: 'VERIFIED_COMPLETE',
        verifiedAt: now,
      };
    });
  }

  async getResponseRecap({ operatorUid, taskId }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    const campaignRef = this.firestore.collection(CAMPAIGN_COLLECTION).doc(taskId);
    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, campaignSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(campaignRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      const campaign = requireCampaign(campaignSnapshot, taskId, operator.rtId);
      const responses = this.firestore.collection(RESPONSE_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('taskId', '==', taskId)
        .limit(MAX_RECAP_RESPONSES);
      const responseSnapshot = await transaction.get(responses);
      const recap = {
        taskId,
        rtId: operator.rtId,
        recordedResponseCount: 0,
        joinedCount: 0,
        declinedCount: 0,
        pendingVerificationCount: 0,
        verifiedCompleteCount: 0,
      };
      for (const snapshot of responseSnapshot.docs) {
        const response = snapshot.data();
        if (response.responseId !== snapshot.id || response.taskId !== taskId ||
            response.rtId !== operator.rtId ||
            responseDocumentId(response.rtId, response.taskId, response.residentId) !==
              snapshot.id) continue;
        recap.recordedResponseCount += 1;
        if (response.participationState === 'JOINED') recap.joinedCount += 1;
        if (response.participationState === 'DECLINED') recap.declinedCount += 1;
        if (response.completionState === 'PENDING_RT_VERIFICATION') {
          recap.pendingVerificationCount += 1;
        }
        if (response.completionState === 'VERIFIED_COMPLETE') {
          recap.verifiedCompleteCount += 1;
        }
      }
      return {
        ...recap,
        isPartial: responseSnapshot.size === MAX_RECAP_RESPONSES,
        taskTitle: campaign.templateSnapshot?.title ?? '',
      };
    });
  }
}

module.exports = {
  FirestoreTaskResponseRepository,
  responseDocumentId,
};
