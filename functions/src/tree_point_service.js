'use strict';

const crypto = require('node:crypto');
const { containsPreciseCoordinates, containsNik } = require('./precise_coordinate_detector');

const TASK_ID_PATTERN = /^[a-f0-9]{40}$/;
const TREE_POINT_ID_PATTERN = /^[a-f0-9]{40}$/;
const EVIDENCE_ID_PATTERN = /^[a-f0-9]{40}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const MAX_SPECIES_HINT_LENGTH = 60;
const MAX_ACCURACY_METERS = 30.0;

class TreePointError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'TreePointError';
    this.code = code;
  }
}

function error(code, message) {
  return new TreePointError(code, message);
}

function invalidArgument(message) {
  return error('invalid-argument', message);
}

function failedPrecondition(message) {
  return error('failed-precondition', message);
}

function permissionDenied(message = 'Akses titik pohon tidak valid.') {
  return error('permission-denied', message);
}

function notFound(message = 'Titik pohon tidak ditemukan.') {
  return error('not-found', message);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    throw invalidArgument('Permintaan titik pohon tidak valid.');
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw invalidArgument('Permintaan titik pohon berisi kolom yang tidak diizinkan.');
  }
}

function validateOperatorAuth(auth) {
  if (typeof auth?.operatorUid !== 'string' || auth.operatorUid.trim().length === 0 ||
      auth.signInProvider !== 'password') {
    throw permissionDenied();
  }
}

function sanitizeSpeciesHint(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw invalidArgument('Jenis pohon tidak valid.');
  const trimmed = value.normalize('NFC').trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > MAX_SPECIES_HINT_LENGTH ||
      containsPreciseCoordinates(trimmed) ||
      containsNik(trimmed) ||
      /\b(?:jalan|jl\.?|gang|gg\.?|rt|rw|nomor|no\.?)\b/iu.test(trimmed)) {
    throw invalidArgument('Nama jenis pohon tidak boleh memuat alamat, koordinat, atau data pribadi.');
  }
  return trimmed;
}

class TreePointService {
  constructor(repository, residentSessionService, clock = () => new Date()) {
    this.repository = repository;
    this.residentSessionService = residentSessionService;
    this.clock = clock;
  }

  async submitTreePoint(data) {
    assertOnlyKeys(data, [
      'sessionToken', 'taskId', 'speciesHint', 'exactLat',
      'exactLng', 'accuracyMeters', 'isMocked', 'evidenceId', 'commandId',
    ]);

    if (typeof data.sessionToken !== 'string') throw permissionDenied();
    const session = await this.residentSessionService.validateSession(data.sessionToken);

    if (typeof data.taskId !== 'string' || !TASK_ID_PATTERN.test(data.taskId)) {
      throw invalidArgument('ID tugas tidak valid.');
    }

    if (typeof data.commandId !== 'string' || !REQUEST_ID_PATTERN.test(data.commandId)) {
      throw invalidArgument('ID perintah idempotency tidak valid.');
    }

    if (typeof data.exactLat !== 'number' || !Number.isFinite(data.exactLat) ||
        data.exactLat < -90.0 || data.exactLat > 90.0) {
      throw invalidArgument('Koordinat latitude tidak valid.');
    }

    if (typeof data.exactLng !== 'number' || !Number.isFinite(data.exactLng) ||
        data.exactLng < -180.0 || data.exactLng > 180.0) {
      throw invalidArgument('Koordinat longitude tidak valid.');
    }

    if (typeof data.accuracyMeters !== 'number' || !Number.isFinite(data.accuracyMeters) ||
        data.accuracyMeters <= 0) {
      throw invalidArgument('Akurasi GPS tidak valid.');
    }

    if (data.accuracyMeters > MAX_ACCURACY_METERS) {
      throw failedPrecondition('Akurasi GPS tidak memadai (maksimal 30 meter). Dekati area terbuka dan coba lagi.');
    }

    if (typeof data.isMocked !== 'boolean') {
      throw invalidArgument('Flag lokasi perangkat tidak valid.');
    }

    if (data.isMocked === true) {
      throw permissionDenied('Lokasi tiruan (mock location) terdeteksi. Gunakan GPS fisik perangkat.');
    }

    let evidenceId = null;
    if (data.evidenceId != null) {
      if (typeof data.evidenceId !== 'string' || !EVIDENCE_ID_PATTERN.test(data.evidenceId)) {
        throw invalidArgument('ID bukti foto tidak valid.');
      }
      evidenceId = data.evidenceId;
    }

    const speciesHint = sanitizeSpeciesHint(data.speciesHint);
    const now = this.clock();

    return this.repository.createTreePoint({
      rtId: session.communityId,
      taskId: data.taskId,
      residentId: session.residentId,
      submitterNickname: session.nickname,
      speciesHint,
      exactLat: data.exactLat,
      exactLng: data.exactLng,
      accuracyMeters: data.accuracyMeters,
      isMocked: data.isMocked,
      evidenceId,
      commandHash: sha256(data.commandId),
      now,
    });
  }

  async listCommunityTreeMap(authOrSessionToken, data = {}) {
    let rtId;
    if (typeof authOrSessionToken === 'object' && authOrSessionToken !== null && authOrSessionToken.operatorUid) {
      validateOperatorAuth(authOrSessionToken);
      rtId = await this.repository.getOperatorRtId(authOrSessionToken.operatorUid);
    } else {
      const token = typeof data.sessionToken === 'string'
        ? data.sessionToken
        : (typeof authOrSessionToken === 'string' ? authOrSessionToken : null);
      if (!token) throw permissionDenied();
      const session = await this.residentSessionService.validateSession(token);
      rtId = session.communityId;
    }

    return this.repository.listCommunityTreeMap({ rtId });
  }

  async verifyTreePoint(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['treePointId', 'decision', 'rejectionReason', 'commandId']);

    if (typeof data.treePointId !== 'string' || !TREE_POINT_ID_PATTERN.test(data.treePointId)) {
      throw invalidArgument('ID titik pohon tidak valid.');
    }

    if (data.decision !== 'APPROVE' && data.decision !== 'REJECT') {
      throw invalidArgument('Keputusan verifikasi harus APPROVE atau REJECT.');
    }

    if (data.decision === 'REJECT') {
      if (typeof data.rejectionReason !== 'string' || data.rejectionReason.trim().length === 0) {
        throw invalidArgument('Alasan penolakan wajib diisi jika menolak.');
      }
    }

    if (typeof data.commandId !== 'string' || !REQUEST_ID_PATTERN.test(data.commandId)) {
      throw invalidArgument('ID perintah tidak valid.');
    }

    const now = this.clock();
    return this.repository.verifyTreePoint({
      operatorUid: auth.operatorUid,
      treePointId: data.treePointId,
      decision: data.decision,
      rejectionReason: data.rejectionReason?.trim() ?? null,
      commandHash: sha256(data.commandId),
      now,
    });
  }

  async deleteTreePoint(auth, data) {
    assertOnlyKeys(data, ['treePointId', 'sessionToken', 'reason']);

    if (typeof data.treePointId !== 'string' || !TREE_POINT_ID_PATTERN.test(data.treePointId)) {
      throw invalidArgument('ID titik pohon tidak valid.');
    }

    const now = this.clock();

    if (auth?.operatorUid && auth?.signInProvider === 'password') {
      return this.repository.deleteTreePoint({
        actorUid: auth.operatorUid,
        isOperator: true,
        treePointId: data.treePointId,
        reason: data.reason ?? 'Dihapus oleh operator RT.',
        now,
      });
    }

    if (typeof data.sessionToken !== 'string') throw permissionDenied();
    const session = await this.residentSessionService.validateSession(data.sessionToken);

    return this.repository.deleteTreePoint({
      actorUid: session.residentId,
      isOperator: false,
      rtId: session.communityId,
      treePointId: data.treePointId,
      reason: data.reason ?? 'Dibatalkan oleh warga pemilik.',
      now,
    });
  }
}

module.exports = {
  TreePointError,
  TreePointService,
  MAX_ACCURACY_METERS,
  MAX_SPECIES_HINT_LENGTH,
};
