const crypto = require('node:crypto');
const { ProxyResidentError } = require('./proxy_resident_service');
const { hashSessionToken } = require('./resident_session_service');

const RESIDENT_ID_PATTERN = /^(?:[a-f0-9]{40}|[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12})$/i;
const COMMAND_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

function fail(code, message) {
  return new ProxyResidentError(code, message);
}
function deny() {
  return fail('permission-denied', 'Akses penghapusan data tidak valid.');
}
function invalid(message = 'Permintaan penghapusan tidak valid.') {
  return fail('invalid-argument', message);
}

class ResidentDataDeletionService {
  constructor(repository, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.clock = clock;
  }

  async deleteOwnResidentData(data) {
    if (!data || typeof data !== 'object' || Array.isArray(data) ||
        Object.keys(data).some((key) => ![
          'sessionToken', 'residentId', 'communityId',
        ].includes(key))) {
      throw invalid('Permintaan berisi kolom yang tidak diizinkan.');
    }
    if (typeof data.residentId !== 'string' || !RESIDENT_ID_PATTERN.test(data.residentId) ||
        typeof data.communityId !== 'string' || data.communityId.trim() !== data.communityId ||
        data.communityId.length < 1 || data.communityId.length > 128) {
      throw invalid();
    }
    const actorSessionHash = hashSessionToken(data.sessionToken);
    const commandHash = crypto.createHash('sha256')
      .update(`resident-self-deletion\0${actorSessionHash}`, 'utf8').digest('hex');
    const result = await this.repository.deleteOwnResidentData({
      residentId: data.residentId,
      rtId: data.communityId,
      actorKind: 'RESIDENT_SELF',
      actorSessionHash,
      commandHash,
      residentRequestConfirmed: true,
      identityVerificationConfirmed: false,
      now: this.clock(),
    });
    return { deleted: result.deleted === true };
  }

  async deleteResidentData(auth, data) {
    if (typeof auth?.operatorUid !== 'string' || !auth.operatorUid.trim() ||
        auth.signInProvider !== 'password') throw deny();
    if (!data || typeof data !== 'object' || Array.isArray(data) ||
        Object.keys(data).some((key) => ![
          'residentId', 'commandId', 'residentRequestConfirmed',
          'identityVerificationConfirmed',
        ].includes(key))) {
      throw invalid('Permintaan berisi kolom yang tidak diizinkan.');
    }
    if (typeof data.residentId !== 'string' || !RESIDENT_ID_PATTERN.test(data.residentId) ||
        typeof data.commandId !== 'string' || !COMMAND_ID_PATTERN.test(data.commandId)) {
      throw invalid();
    }
    if (data.residentRequestConfirmed !== true || data.identityVerificationConfirmed !== true) {
      throw fail(
        'failed-precondition',
        'Pastikan warga meminta penghapusan dan identitasnya diverifikasi melalui prosedur pilot.',
      );
    }
    const commandHash = crypto.createHash('sha256').update(data.commandId, 'utf8').digest('hex');
    const result = await this.repository.deleteResidentData({
      operatorUid: auth.operatorUid,
      residentId: data.residentId,
      commandHash,
      residentRequestConfirmed: true,
      identityVerificationConfirmed: true,
      now: this.clock(),
    });
    return { residentId: data.residentId, deleted: result.deleted === true };
  }
}

module.exports = { ResidentDataDeletionService };
