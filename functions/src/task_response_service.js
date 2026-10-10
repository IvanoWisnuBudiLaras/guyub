const crypto = require('node:crypto');
const { hashSessionToken } = require('./resident_session_service');
const { containsPreciseCoordinates, containsNik } = require('./precise_coordinate_detector');
const { TaskCampaignError, asDate } = require('./task_campaign_service');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const TASK_ID_PATTERN = /^[a-f0-9]{40}$/;
const EVIDENCE_ID_PATTERN = /^[a-f0-9]{40}$/;
const RESPONSE_ID_PATTERN = /^[a-f0-9]{40}$/;
const RESIDENT_NOTE_LIMIT = 500;

function error(code, message) {
  return new TaskCampaignError(code, message);
}

function permissionDenied() {
  return error('permission-denied', 'Akses tugas tidak valid.');
}

function invalidArgument(message) {
  return error('invalid-argument', message);
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    throw invalidArgument('Permintaan tugas tidak valid.');
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw invalidArgument('Permintaan tugas berisi kolom yang tidak diizinkan.');
  }
}

function validateOperatorAuth(auth) {
  if (typeof auth?.operatorUid !== 'string' || auth.operatorUid.trim().length === 0 ||
      auth.signInProvider !== 'password') {
    throw permissionDenied();
  }
}

function requireTaskId(value) {
  if (typeof value !== 'string' || !TASK_ID_PATTERN.test(value)) {
    throw invalidArgument('Tugas tidak valid.');
  }
  return value;
}

function requireRequestId(value) {
  if (typeof value !== 'string' || !REQUEST_ID_PATTERN.test(value)) {
    throw invalidArgument('Permintaan tugas tidak valid.');
  }
  return value;
}

function normalizeCompletionNote(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw invalidArgument('Catatan penyelesaian tidak valid.');
  const note = value.normalize('NFC').trim();
  if (note.length === 0) return null;
  const numberCheckText = note.replace(/[()]/gu, '');
  if ([...note].length > RESIDENT_NOTE_LIMIT ||
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(note) ||
      containsPreciseCoordinates(note) ||
      /\b(?:alamat|rumah|jalan|jl\.?|gang|gg\.?|blok|perumahan)\b/iu.test(note) ||
      /\b(?:no\.?|nomor)\s*\d/iu.test(note) ||
      containsNik(note) ||
      /(?<!\d)(?:(?:\+?62|0)[\s()./-]*)8(?:[\s()./-]*\d){8,11}(?!\d)/u.test(numberCheckText)) {
    throw invalidArgument('Gunakan catatan singkat tanpa alamat, data pribadi, atau koordinat GPS.');
  }
  return note;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function responseDocumentId(rtId, taskId, residentId) {
  return sha256(`${rtId}\0${taskId}\0${residentId}`).slice(0, 40);
}

function iso(value) {
  const date = asDate(value);
  return date ? date.toISOString() : null;
}

function residentTask(campaign, response) {
  return {
    taskId: campaign.campaignId,
    rtId: campaign.rtId,
    templateSnapshot: campaign.templateSnapshot,
    deadline: iso(campaign.deadline),
    locationReference: campaign.locationReference ?? null,
    status: campaign.status,
    participationState: response?.participationState ?? 'UNRESPONDED',
    completionState: response?.completionState ?? 'NOT_SUBMITTED',
    completionNote: response?.completionNote ?? null,
    completionSubmittedAt: iso(response?.completionSubmittedAt),
    verifiedAt: iso(response?.verifiedAt),
    evidenceId: response?.evidenceId ?? null,
  };
}

function residentResponse(response) {
  return {
    taskId: response.taskId,
    participationState: response.participationState,
    completionState: response.completionState,
    completionNote: response.completionNote ?? null,
    completionSubmittedAt: iso(response.completionSubmittedAt),
    verifiedAt: iso(response.verifiedAt),
    evidenceId: response.evidenceId ?? null,
  };
}

function pendingVerification(row) {
  return {
    responseId: row.responseId,
    taskId: row.taskId,
    taskTitle: row.taskTitle,
    nickname: row.nickname,
    completionNote: row.completionNote ?? null,
    submittedAt: iso(row.completionSubmittedAt),
    evidenceId: row.evidenceId ?? null,
  };
}

class TaskResponseService {
  constructor(repository, residentSessionService, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.residentSessionService = residentSessionService;
    this.clock = clock;
  }

  async listResidentActiveTasks(data) {
    assertOnlyKeys(data, ['sessionToken']);
    const session = await this._residentSession(data.sessionToken);
    const result = await this.repository.listActiveTasks({
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      now: this.clock(),
    });
    return {
      items: result.items.map(({ campaign, response }) => residentTask(campaign, response)),
      isPartial: result.isPartial,
    };
  }

  async recordResidentTaskResponse(data) {
    assertOnlyKeys(data, ['sessionToken', 'taskId', 'choice', 'commandId']);
    const taskId = requireTaskId(data.taskId);
    const commandId = requireRequestId(data.commandId);
    if (data.choice !== 'JOINED' && data.choice !== 'DECLINED') {
      throw invalidArgument('Pilih Ikut atau Tidak Ikut.');
    }
    const session = await this._residentSession(data.sessionToken);
    const response = await this.repository.recordParticipation({
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      taskId,
      choice: data.choice,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return residentResponse(response);
  }

  async submitTaskCompletion(data) {
    assertOnlyKeys(data, ['sessionToken', 'taskId', 'note', 'commandId', 'evidenceId']);
    const taskId = requireTaskId(data.taskId);
    const commandId = requireRequestId(data.commandId);
    const completionNote = normalizeCompletionNote(data.note);
    const evidenceId = data.evidenceId ?? null;
    if (evidenceId !== null && (typeof evidenceId !== 'string' || !EVIDENCE_ID_PATTERN.test(evidenceId))) {
      throw invalidArgument('Bukti tugas tidak valid.');
    }
    const session = await this._residentSession(data.sessionToken);
    const response = await this.repository.submitCompletion({
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      taskId,
      completionNote,
      evidenceId,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return residentResponse(response);
  }

  async listPendingTaskVerifications(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const result = await this.repository.listPendingVerifications({
      operatorUid: auth.operatorUid,
    });
    return {
      items: result.items.map(pendingVerification),
      isPartial: result.isPartial,
    };
  }

  async verifyTaskCompletion(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['responseId', 'commandId']);
    if (typeof data.responseId !== 'string' || !RESPONSE_ID_PATTERN.test(data.responseId)) {
      throw invalidArgument('Respons tugas tidak valid.');
    }
    const commandId = requireRequestId(data.commandId);
    const response = await this.repository.verifyCompletion({
      operatorUid: auth.operatorUid,
      responseId: data.responseId,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return residentResponse(response);
  }

  async getTaskResponseRecap(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['taskId']);
    const taskId = requireTaskId(data.taskId);
    return this.repository.getResponseRecap({
      operatorUid: auth.operatorUid,
      taskId,
    });
  }

  async _residentSession(token) {
    if (typeof token !== 'string') throw permissionDenied();
    return this.residentSessionService.validateSession(token);
  }
}

module.exports = {
  REQUEST_ID_PATTERN,
  RESIDENT_NOTE_LIMIT,
  RESPONSE_ID_PATTERN,
  TASK_ID_PATTERN,
  TaskResponseService,
  normalizeCompletionNote,
  responseDocumentId,
};
