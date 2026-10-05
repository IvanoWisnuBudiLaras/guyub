const crypto = require('node:crypto');
const { hashSessionToken } = require('./resident_session_service');
const { ProxyResidentError } = require('./proxy_resident_service');

const RESIDENT_ID_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})$/i;
const ASSIGNMENT_ID_PATTERN = /^[a-f0-9]{40}$/;
const COMMAND_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function fail(code, message) {
  return new ProxyResidentError(code, message);
}
function deny() {
  return fail('permission-denied', 'Akses bantuan relawan tidak valid.');
}
function invalid(message = 'Permintaan bantuan relawan tidak valid.') {
  return fail('invalid-argument', message);
}
function requireKeys(data, allowed) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowed.includes(key))) {
    throw invalid('Permintaan berisi kolom yang tidak diizinkan.');
  }
}
function validateOperator(auth) {
  if (typeof auth?.operatorUid !== 'string' || !auth.operatorUid.trim() ||
      auth.signInProvider !== 'password') throw deny();
}
function commandHash(commandId) {
  if (typeof commandId !== 'string' || !COMMAND_ID_PATTERN.test(commandId)) throw invalid();
  return crypto.createHash('sha256').update(commandId, 'utf8').digest('hex');
}

class AssistanceAssignmentService {
  constructor(repository, sessions, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.sessions = sessions;
    this.clock = clock;
  }

  async getVolunteerData(data) {
    requireKeys(data, ['sessionToken']);
    const session = await this._requireResidentSession(data.sessionToken);
    return this.repository.getVolunteerData({
      ...session,
      sessionIdHash: hashSessionToken(data.sessionToken),
      now: this.clock(),
    });
  }

  async updateVolunteerConsent(data) {
    requireKeys(data, [
      'sessionToken', 'willingToHelp', 'residentConsentConfirmed', 'commandId',
    ]);
    if (typeof data.willingToHelp !== 'boolean') throw invalid('Pilihan relawan tidak valid.');
    if (data.residentConsentConfirmed !== true) {
      throw fail('failed-precondition', 'Konfirmasi kesediaan sukarela wajib diberikan.');
    }
    const session = await this._requireResidentSession(data.sessionToken);
    return this.repository.updateVolunteerConsent({
      ...session,
      sessionIdHash: hashSessionToken(data.sessionToken),
      willingToHelp: data.willingToHelp,
      commandHash: commandHash(data.commandId),
      residentConsentConfirmed: true,
      now: this.clock(),
    });
  }

  async listVolunteerHelpers(auth, data) {
    validateOperator(auth);
    requireKeys(data, []);
    return this.repository.listVolunteerHelpers({
      operatorUid: auth.operatorUid,
    });
  }

  async createHelperAssignment(auth, data) {
    validateOperator(auth);
    requireKeys(data, ['residentId', 'helperResidentId', 'commandId']);
    if (typeof data.residentId !== 'string' || !RESIDENT_ID_PATTERN.test(data.residentId) ||
        typeof data.helperResidentId !== 'string' ||
        !RESIDENT_ID_PATTERN.test(data.helperResidentId)) throw invalid();
    return this.repository.createHelperAssignment({
      operatorUid: auth.operatorUid,
      residentId: data.residentId,
      helperResidentId: data.helperResidentId,
      commandHash: commandHash(data.commandId),
      now: this.clock(),
    });
  }

  async respondToHelperAssignment(data) {
    requireKeys(data, [
      'sessionToken', 'assignmentId', 'decision', 'residentConsentConfirmed', 'commandId',
    ]);
    if (typeof data.assignmentId !== 'string' ||
        !ASSIGNMENT_ID_PATTERN.test(data.assignmentId) ||
        !['ACCEPTED', 'DECLINED', 'WITHDRAWN'].includes(data.decision)) throw invalid();
    if (data.residentConsentConfirmed !== true) {
      throw fail('failed-precondition', 'Konfirmasi pilihan relawan wajib diberikan.');
    }
    const session = await this._requireResidentSession(data.sessionToken);
    return this.repository.respondToHelperAssignment({
      ...session,
      sessionIdHash: hashSessionToken(data.sessionToken),
      assignmentId: data.assignmentId,
      decision: data.decision,
      commandHash: commandHash(data.commandId),
      residentConsentConfirmed: true,
      now: this.clock(),
    });
  }

  async _requireResidentSession(token) {
    if (typeof token !== 'string') throw deny();
    const session = await this.sessions.validateSession(token);
    if (!session || typeof session.residentId !== 'string' ||
        typeof session.communityId !== 'string') throw deny();
    return { residentId: session.residentId, rtId: session.communityId };
  }
}

module.exports = { AssistanceAssignmentService };
