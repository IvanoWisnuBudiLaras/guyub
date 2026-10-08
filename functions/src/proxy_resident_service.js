const crypto = require('node:crypto');
const { containsForbiddenPersonalData } = require('./resident_proposal_service');
const { OPERATOR_ROLES, asDate } = require('./task_campaign_service');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const ID_PATTERN = /^[a-f0-9]{40}$/;
const NICKNAME_LIMIT = 40;
const HOUSE_NUMBER_PATTERN = /^[A-Za-z0-9-]{1,12}$/;

class ProxyResidentError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ProxyResidentError';
    this.code = code;
  }
}

function invalidArgument(message = 'Data warga tidak valid.') {
  return new ProxyResidentError('invalid-argument', message);
}
function permissionDenied() {
  return new ProxyResidentError('permission-denied', 'Akses warga tidak valid.');
}
function failedPrecondition(message = 'Status warga tidak dapat diperbarui.') {
  return new ProxyResidentError('failed-precondition', message);
}
function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}
function assertOnlyKeys(data, allowedKeys) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowedKeys.includes(key))) {
    throw invalidArgument('Permintaan berisi kolom yang tidak diizinkan.');
  }
}
function validateOperatorAuth(auth) {
  if (typeof auth?.operatorUid !== 'string' || auth.operatorUid.trim().length === 0 ||
      auth.signInProvider !== 'password') throw permissionDenied();
}
function requireRequestId(value) {
  if (typeof value !== 'string' || !REQUEST_ID_PATTERN.test(value)) {
    throw invalidArgument('ID permintaan tidak valid.');
  }
  return value;
}
function requireResidentId(value) {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) {
    throw invalidArgument('Warga tidak valid.');
  }
  return value;
}
function requireTaskId(value) {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) {
    throw invalidArgument('Tugas tidak valid.');
  }
  return value;
}
function normalizeProxyNickname(value) {
  if (typeof value !== 'string') throw invalidArgument('Nama panggilan wajib diisi.');
  const nickname = value.normalize('NFC').trim();
  if (!nickname || [...nickname].length > NICKNAME_LIMIT ||
      /[\u0000-\u001F\u007F]/u.test(nickname) || containsForbiddenPersonalData(nickname)) {
    throw invalidArgument('Gunakan nama panggilan tanpa alamat atau data pribadi.');
  }
  return nickname;
}
function normalizeHouseNumber(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string') throw invalidArgument('Nomor rumah tidak valid.');
  const houseNumber = value.normalize('NFC').trim();
  if (!HOUSE_NUMBER_PATTERN.test(houseNumber) || containsForbiddenPersonalData(houseNumber)) {
    throw invalidArgument('Gunakan nomor rumah singkat saja, tanpa alamat.');
  }
  return houseNumber;
}
function requireConsent(value) {
  if (value !== true) throw failedPrecondition(
    'Pastikan warga telah menyetujui pencatatan atau mengonfirmasi pilihan ini.',
  );
}
function proxyResidentDocumentId(rtId, requestId) {
  return sha256(`proxy-resident\0${rtId}\0${sha256(requestId)}`).slice(0, 40);
}
function iso(value) {
  const date = asDate(value);
  return date ? date.toISOString() : null;
}
function publicProxyResident(record) {
  return {
    residentId: record.residentId,
    nickname: record.nickname,
    houseNumber: record.houseNumber ?? null,
    needsAssistance: record.needsAssistance === true,
    createdAt: iso(record.createdAt),
  };
}
function publicProxyStatus(record) {
  return {
    taskId: record.taskId,
    participationState: record.participationState,
    completionState: record.completionState,
  };
}

class ProxyResidentService {
  constructor(repository, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.clock = clock;
  }

  async createProxyResident(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, [
      'nickname', 'houseNumber', 'needsAssistance', 'residentConsentConfirmed', 'requestId',
    ]);
    const requestId = requireRequestId(data.requestId);
    const nickname = normalizeProxyNickname(data.nickname);
    const houseNumber = normalizeHouseNumber(data.houseNumber);
    const needsAssistance = data.needsAssistance ?? false;
    if (typeof needsAssistance !== 'boolean') throw invalidArgument('Status bantuan tidak valid.');
    requireConsent(data.residentConsentConfirmed);
    const requestHash = sha256(requestId);
    const rtId = await this.repository.getOperatorRtId(auth.operatorUid);
    const now = this.clock();
    const result = await this.repository.createProxyResident({
      operatorUid: auth.operatorUid,
      expectedRtId: rtId,
      residentId: proxyResidentDocumentId(rtId, requestId),
      requestHash,
      nickname,
      houseNumber,
      needsAssistance,
      residentConsentConfirmed: true,
      now,
    });
    return publicProxyResident(result);
  }

  async listProxyResidents(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const result = await this.repository.listProxyResidents({ operatorUid: auth.operatorUid });
    return {
      items: result.items.map(publicProxyResident),
      isPartial: result.isPartial,
    };
  }

  async getProxyTaskStatus(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['residentId', 'taskId']);
    const residentId = requireResidentId(data.residentId);
    const taskId = requireTaskId(data.taskId);
    const rtId = await this.repository.getOperatorRtId(auth.operatorUid);
    const record = await this.repository.getProxyTaskStatus({
      operatorUid: auth.operatorUid,
      rtId,
      residentId,
      taskId,
    });
    return publicProxyStatus(record);
  }

  async updateProxyAssistance(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, [
      'residentId', 'needsAssistance', 'residentConsentConfirmed', 'commandId',
    ]);
    const residentId = requireResidentId(data.residentId);
    if (typeof data.needsAssistance !== 'boolean') throw invalidArgument('Status bantuan tidak valid.');
    const commandId = requireRequestId(data.commandId);
    requireConsent(data.residentConsentConfirmed);
    const record = await this.repository.updateProxyAssistance({
      operatorUid: auth.operatorUid,
      residentId,
      needsAssistance: data.needsAssistance,
      residentConsentConfirmed: true,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return { residentId: record.residentId, needsAssistance: record.needsAssistance };
  }

  async updateProxyTaskStatus(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, [
      'residentId', 'taskId', 'participationState', 'completionReported',
      'residentConsentConfirmed', 'commandId',
    ]);
    const residentId = requireResidentId(data.residentId);
    const taskId = requireTaskId(data.taskId);
    if (!['JOINED', 'DECLINED'].includes(data.participationState)) {
      throw invalidArgument('Pilih status Ikut atau Tidak Ikut.');
    }
    if (typeof data.completionReported !== 'boolean') {
      throw invalidArgument('Status penyelesaian tidak valid.');
    }
    if (data.completionReported && data.participationState !== 'JOINED') {
      throw invalidArgument('Penyelesaian hanya dapat dilaporkan untuk warga yang ikut.');
    }
    const commandId = requireRequestId(data.commandId);
    requireConsent(data.residentConsentConfirmed);
    const rtId = await this.repository.getOperatorRtId(auth.operatorUid);
    const record = await this.repository.updateProxyTaskStatus({
      operatorUid: auth.operatorUid,
      rtId,
      residentId,
      taskId,
      participationState: data.participationState,
      completionReported: data.completionReported,
      residentConsentConfirmed: true,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return publicProxyStatus(record);
  }
}

module.exports = {
  ID_PATTERN,
  ProxyResidentError,
  ProxyResidentService,
  normalizeHouseNumber,
  normalizeProxyNickname,
  proxyResidentDocumentId,
};
