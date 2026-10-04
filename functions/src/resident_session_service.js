const crypto = require('node:crypto');

const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const GENERIC_ACCESS_MESSAGE = 'Kode RT tidak valid atau tidak aktif.';
const GENERIC_SESSION_MESSAGE = 'Sesi warga tidak valid atau sudah berakhir.';
const JOIN_CODE_PATTERN = /^[A-Z0-9]{12,32}$/;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const ENROLLMENT_REQUEST_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

class SessionServiceError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'SessionServiceError';
    this.code = code;
  }
}

function normalizeJoinCode(value) {
  if (typeof value !== 'string') throw accessDenied();
  const code = value.trim().toUpperCase();
  if (!JOIN_CODE_PATTERN.test(code)) throw accessDenied();
  return code;
}

function normalizeNickname(value) {
  if (typeof value !== 'string') {
    throw new SessionServiceError('invalid-argument', 'Nama panggilan wajib diisi.');
  }
  const nickname = value.normalize('NFC').trim();
  const length = [...nickname].length;
  if (length < 1 || length > 40 || /[\u0000-\u001F\u007F]/u.test(nickname)) {
    throw new SessionServiceError('invalid-argument', 'Nama panggilan tidak valid.');
  }
  return nickname;
}

function hashJoinCode(value) {
  return crypto.createHash('sha256').update(normalizeJoinCode(value), 'utf8').digest('hex');
}

function hashSessionToken(value) {
  if (typeof value !== 'string' || !TOKEN_PATTERN.test(value)) {
    throw sessionDenied();
  }
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function hashEnrollmentRequestId(value) {
  if (typeof value !== 'string' || !ENROLLMENT_REQUEST_PATTERN.test(value)) {
    throw new SessionServiceError('invalid-argument', 'Permintaan pendaftaran tidak valid.');
  }
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function fingerprintEnrollment(joinCodeHash, nickname) {
  return crypto.createHash('sha256')
    .update(`${joinCodeHash}\0${nickname}`, 'utf8')
    .digest('hex');
}

function accessDenied() {
  return new SessionServiceError('permission-denied', GENERIC_ACCESS_MESSAGE);
}

function sessionDenied() {
  return new SessionServiceError('permission-denied', GENERIC_SESSION_MESSAGE);
}

function asDate(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') return new Date(value);
  return null;
}

class ResidentSessionService {
  constructor(repository, {
    clock = () => new Date(),
    tokenFactory = () => crypto.randomBytes(32).toString('base64url'),
    idFactory = () => crypto.randomUUID(),
  } = {}) {
    this.repository = repository;
    this.clock = clock;
    this.tokenFactory = tokenFactory;
    this.idFactory = idFactory;
  }

  async createSession({ joinCode, nickname, requestId }) {
    const requestHash = hashEnrollmentRequestId(requestId);
    const code = normalizeJoinCode(joinCode);
    const cleanNickname = normalizeNickname(nickname);
    const expectedJoinCodeHash = hashJoinCode(code);
    const requestFingerprint = fingerprintEnrollment(expectedJoinCodeHash, cleanNickname);
    const community = await this.repository.findCommunityByJoinCodeHash(expectedJoinCodeHash);
    if (!community || !community.joinCodeActive || !community.id || !community.rtLabel) {
      throw accessDenied();
    }

    const now = this.clock();
    const expiresAt = new Date(now.getTime() + SESSION_TTL_MS);
    const sessionToken = this.tokenFactory();
    const sessionId = hashSessionToken(sessionToken);
    const residentId = this.idFactory();
    const resident = {
      rtId: community.id,
      nickname: cleanNickname,
      needsAssistance: false,
      createdBy: 'self',
      createdAt: now,
      updatedAt: now,
    };
    const session = {
      residentId,
      rtId: community.id,
      active: true,
      createdAt: now,
      expiresAt,
    };

    const enrollment = await this.repository.createResidentAndSession({
      communityId: community.id,
      expectedJoinCodeHash,
      requestHash,
      requestFingerprint,
      residentId,
      resident,
      sessionId,
      session,
    });
    return {
      residentId: enrollment.residentId,
      communityId: community.id,
      communityName: community.displayName,
      rtLabel: community.rtLabel,
      nickname: cleanNickname,
      sessionToken,
      expiresAt,
    };
  }

  async validateSession(token) {
    const sessionId = hashSessionToken(token);
    const session = await this.repository.getSession(sessionId);
    const now = this.clock();
    const expiresAt = asDate(session?.expiresAt);
    if (!session || session.active !== true || !expiresAt || expiresAt <= now) {
      throw sessionDenied();
    }
    const resident = await this.repository.getResident(session.residentId);
    if (!resident || resident.rtId !== session.rtId || typeof resident.nickname !== 'string') {
      throw sessionDenied();
    }
    const community = await this.repository.getCommunity(session.rtId);
    if (!community || community.id !== session.rtId) throw sessionDenied();
    return {
      residentId: session.residentId,
      communityId: session.rtId,
      communityName: community.displayName,
      rtLabel: community.rtLabel,
      nickname: resident.nickname,
      expiresAt,
    };
  }

  async revokeSession(token) {
    const sessionId = hashSessionToken(token);
    await this.repository.revokeSession(sessionId, this.clock());
  }
}

module.exports = {
  GENERIC_ACCESS_MESSAGE,
  GENERIC_SESSION_MESSAGE,
  JOIN_CODE_PATTERN,
  ENROLLMENT_REQUEST_PATTERN,
  SESSION_TTL_MS,
  ResidentSessionService,
  SessionServiceError,
  hashEnrollmentRequestId,
  hashJoinCode,
  hashSessionToken,
  normalizeJoinCode,
  normalizeNickname,
  fingerprintEnrollment,
};
