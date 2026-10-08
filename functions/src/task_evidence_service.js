const crypto = require('node:crypto');
const sharp = require('sharp');
const { TaskCampaignError } = require('./task_campaign_service');
const { hashSessionToken } = require('./resident_session_service');

const DAY_MS = 24 * 60 * 60 * 1000;
const EVIDENCE_RETENTION_DAYS = 30;
const MAX_IMAGE_INPUT_BYTES = 3 * 1024 * 1024;
const MAX_IMAGE_OUTPUT_BYTES = 2 * 1024 * 1024;
const MAX_IMAGE_PIXELS = 12_000_000;
const MAX_IMAGE_EDGE = 1280;
const MAX_CLEANUP_BATCH = 100;
const TASK_ID_PATTERN = /^[a-f0-9]{40}$/u;
const EVIDENCE_ID_PATTERN = /^[a-f0-9]{40}$/u;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/u;
const BASE64_PATTERN = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/u;

function invalidArgument(message = 'Permintaan bukti tidak valid.') {
  return new TaskCampaignError('invalid-argument', message);
}

function failedPrecondition(message = 'Bukti tidak dapat diproses.') {
  return new TaskCampaignError('failed-precondition', message);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function residentScopeHash(rtId, residentId) {
  return sha256(`${rtId}\0${residentId}`);
}

function deriveEvidenceId(rtId, residentId, taskId, commandHash) {
  return sha256(`${rtId}\0${residentId}\0${taskId}\0${commandHash}`).slice(0, 40);
}

function buildStoragePath(rtId, taskId, residentId, evidenceId) {
  return `evidence/${sha256(rtId).slice(0, 20)}/${sha256(residentId).slice(0, 40)}/${evidenceId}.jpg`;
}

function decodeImageBase64(value) {
  if (typeof value !== 'string' || value.length === 0 ||
      value.length > Math.ceil(MAX_IMAGE_INPUT_BYTES * 4 / 3) + 4 ||
      !BASE64_PATTERN.test(value)) {
    throw invalidArgument('Foto bukti tidak valid atau terlalu besar.');
  }
  const decoded = Buffer.from(value, 'base64');
  if (decoded.length === 0 || decoded.length > MAX_IMAGE_INPUT_BYTES ||
      decoded.toString('base64') !== value) {
    throw invalidArgument('Foto bukti tidak valid atau terlalu besar.');
  }
  return decoded;
}

async function sanitizeEvidenceJpeg(input, sharpFactory = sharp) {
  if (!Buffer.isBuffer(input) || input.length === 0 || input.length > MAX_IMAGE_INPUT_BYTES) {
    throw invalidArgument('Foto bukti tidak valid atau terlalu besar.');
  }
  let metadata;
  try {
    metadata = await sharpFactory(input, {
      failOn: 'error',
      limitInputPixels: MAX_IMAGE_PIXELS,
    }).metadata();
  } catch (_) {
    throw invalidArgument('Foto bukti tidak dapat dibaca.');
  }
  if (metadata.format !== 'jpeg' || !Number.isSafeInteger(metadata.width) ||
      !Number.isSafeInteger(metadata.height) || metadata.width < 1 || metadata.height < 1 ||
      metadata.width * metadata.height > MAX_IMAGE_PIXELS || (metadata.pages ?? 1) !== 1) {
    throw invalidArgument('Unggah foto JPEG yang valid.');
  }

  let output;
  for (const quality of [82, 72, 62, 52]) {
    try {
      output = await sharpFactory(input, {
        failOn: 'error',
        limitInputPixels: MAX_IMAGE_PIXELS,
      })
        .rotate()
        .resize({
          width: MAX_IMAGE_EDGE,
          height: MAX_IMAGE_EDGE,
          fit: 'inside',
          withoutEnlargement: true,
        })
        .jpeg({ quality, mozjpeg: true })
        .toBuffer();
    } catch (_) {
      throw invalidArgument('Foto bukti tidak dapat dibaca.');
    }
    if (output.length <= MAX_IMAGE_OUTPUT_BYTES) break;
  }
  if (!output || output.length > MAX_IMAGE_OUTPUT_BYTES) {
    throw invalidArgument('Ukuran foto bukti terlalu besar.');
  }

  // A fresh libvips output strips source EXIF, GPS, XMP, IPTC, comments, and profiles.
  let outputMetadata;
  try {
    outputMetadata = await sharpFactory(output, { failOn: 'error' }).metadata();
  } catch (_) {
    throw failedPrecondition('Foto bukti tidak dapat disiapkan.');
  }
  if (outputMetadata.format !== 'jpeg' || outputMetadata.exif !== undefined ||
      outputMetadata.iptc !== undefined || outputMetadata.xmp !== undefined ||
      outputMetadata.icc !== undefined) {
    throw failedPrecondition('Metadata foto bukti tidak dapat dihapus.');
  }
  return output;
}

function requireInputObject(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some((key) => !keys.includes(key))) {
    throw invalidArgument();
  }
}

function requireTaskId(value) {
  if (typeof value !== 'string' || !TASK_ID_PATTERN.test(value)) {
    throw invalidArgument('Tugas tidak valid.');
  }
}

function requireEvidenceId(value) {
  if (typeof value !== 'string' || !EVIDENCE_ID_PATTERN.test(value)) {
    throw invalidArgument();
  }
}

class TaskEvidenceService {
  constructor(repository, residentSessionService, storage, options = {}) {
    this.repository = repository;
    this.residentSessionService = residentSessionService;
    this.storage = storage;
    this.clock = options.clock ?? (() => new Date());
    this.sanitizeImage = options.sanitizeImage ?? sanitizeEvidenceJpeg;
  }

  async uploadResidentEvidence(data) {
    requireInputObject(data, ['sessionToken', 'taskId', 'requestId', 'imageBase64']);
    requireTaskId(data.taskId);
    if (typeof data.requestId !== 'string' || !REQUEST_ID_PATTERN.test(data.requestId)) {
      throw invalidArgument('Permintaan unggah tidak valid.');
    }
    const session = await this.residentSessionService.validateSession(data.sessionToken);
    this.storage.assertConfigured?.();
    const sessionIdHash = hashSessionToken(data.sessionToken);
    const inputBytes = decodeImageBase64(data.imageBase64);
    const sanitizedBytes = await this.sanitizeImage(inputBytes);
    const now = this.clock();
    const commandHash = sha256(data.requestId);
    const imageHash = sha256(sanitizedBytes);
    const evidenceId = deriveEvidenceId(session.communityId, session.residentId, data.taskId, commandHash);
    const scopeHash = residentScopeHash(session.communityId, session.residentId);
    const storagePath = buildStoragePath(session.communityId, data.taskId, session.residentId, evidenceId);
    const expiresAt = new Date(now.getTime() + EVIDENCE_RETENTION_DAYS * DAY_MS);
    const reservation = await this.repository.reserveUpload({
      evidenceId,
      rtId: session.communityId,
      residentId: session.residentId,
      residentScopeHash: scopeHash,
      sessionIdHash,
      taskId: data.taskId,
      commandHash,
      contentHash: imageHash,
      storagePath,
      now,
      expiresAt,
    });
    if (!['READY', 'UPLOADING'].includes(reservation.status)) {
      throw failedPrecondition('Bukti yang sudah dihapus tidak dapat dipulihkan.');
    }
    const storedExpiry = reservation.expiresAt instanceof Date
      ? reservation.expiresAt
      : reservation.expiresAt && typeof reservation.expiresAt.toDate === 'function'
        ? reservation.expiresAt.toDate()
        : new Date(reservation.expiresAt);
    if (!Number.isFinite(storedExpiry.getTime()) || storedExpiry <= now) {
      throw failedPrecondition('Masa unggah foto bukti sudah berakhir.');
    }
    if (reservation.status === 'UPLOADING') {
      try {
        await this.storage.save(storagePath, sanitizedBytes, {
          contentType: 'image/jpeg',
          cacheControl: 'private, no-store',
          evidenceId,
        });
      } catch (error) {
        if (error instanceof TaskCampaignError) throw error;
        throw new TaskCampaignError('unavailable', 'Bukti belum dapat disimpan. Coba lagi.');
      }
      try {
        await this.repository.markReady({
          evidenceId,
          rtId: session.communityId,
          residentScopeHash: scopeHash,
          contentHash: imageHash,
          now: this.clock(),
        });
      } catch (error) {
        // A definitive state conflict means deletion won the race. A transient
        // Firestore error may follow a committed READY transition, so keep the
        // object and let the deterministic retry reconcile it.
        if (error instanceof TaskCampaignError && error.code === 'failed-precondition') {
          await this.storage.delete(storagePath).catch(() => {});
          throw error;
        }
        if (error instanceof TaskCampaignError) throw error;
        throw new TaskCampaignError('unavailable', 'Bukti belum dapat disimpan. Coba lagi.');
      }
    }
    return { evidenceId, expiresAt: storedExpiry.toISOString() };
  }

  async getEvidenceForOperator(auth, data) {
    if (typeof auth?.operatorUid !== 'string' || !auth.operatorUid.trim() ||
        auth.signInProvider !== 'password') {
      throw new TaskCampaignError('permission-denied', 'Akses operator tidak valid.');
    }
    requireInputObject(data, ['evidenceId']);
    requireEvidenceId(data.evidenceId);
    const record = await this.repository.getForOperator({
      operatorUid: auth.operatorUid,
      evidenceId: data.evidenceId,
      now: this.clock(),
    });
    let bytes;
    try {
      bytes = await this.storage.read(record.storagePath);
    } catch (_) {
      throw new TaskCampaignError('unavailable', 'Foto bukti belum dapat dibuka.');
    }
    if (!Buffer.isBuffer(bytes) || bytes.length === 0 || bytes.length > MAX_IMAGE_OUTPUT_BYTES) {
      throw failedPrecondition('Foto bukti tidak dapat dibuka.');
    }
    return {
      evidenceId: data.evidenceId,
      contentType: 'image/jpeg',
      imageBase64: bytes.toString('base64'),
    };
  }

  async deleteResidentEvidence(data) {
    requireInputObject(data, ['sessionToken', 'evidenceId', 'commandId']);
    requireEvidenceId(data.evidenceId);
    if (typeof data.commandId !== 'string' || !REQUEST_ID_PATTERN.test(data.commandId)) {
      throw invalidArgument('Permintaan penghapusan tidak valid.');
    }
    const session = await this.residentSessionService.validateSession(data.sessionToken);
    this.storage.assertConfigured?.();
    const input = {
      evidenceId: data.evidenceId,
      rtId: session.communityId,
      residentId: session.residentId,
      residentScopeHash: residentScopeHash(session.communityId, session.residentId),
      sessionIdHash: hashSessionToken(data.sessionToken),
      commandHash: sha256(data.commandId),
      now: this.clock(),
    };
    const record = await this.repository.requestResidentDeletion(input);
    await this._deleteObject(record, input.now);
    return { deleted: true };
  }

  // [cleanup-bukti:isolasi-starvasi]: Paginasi multi-batch dengan cursor; item gagal tidak memblokir record berikutnya.
  async deleteExpiredEvidence(options = {}) {
    const now = options.now ?? this.clock();
    const batchSize = options.batchSize ?? MAX_CLEANUP_BATCH;
    const maxBatches = options.maxBatches ?? 20;
    let examined = 0;
    let deleted = 0;
    let retryPending = 0;
    let lastRecord = null;

    for (let batch = 0; batch < maxBatches; batch += 1) {
      const records = await this.repository.listDueEvidence({
        now,
        limit: batchSize,
        startAfterDoc: lastRecord?._doc,
        startAfterEvidenceId: lastRecord?.evidenceId,
      });
      if (!records || records.length === 0) break;

      for (const candidate of records) {
        lastRecord = candidate;
        const record = await this.repository.beginExpiredDeletion({
          evidenceId: candidate.evidenceId,
          now,
        });
        if (!record) continue;
        try {
          await this.storage.delete(record.storagePath);
          await this.repository.markDeleted({ evidenceId: record.evidenceId, now });
          deleted += 1;
        } catch (_) {
          await this.repository.markDeleteFailed({
            evidenceId: record.evidenceId,
            now,
            errorCode: 'storage-delete-failed',
          });
          console.warn('Task evidence deletion remains pending.', {
            evidenceId: record.evidenceId,
            errorCode: 'storage-delete-failed',
          });
          retryPending += 1;
        }
      }
      examined += records.length;
      if (records.length < batchSize) break;
    }

    return { examined, deleted, retryPending };
  }

  async _deleteObject(record, now) {
    if (record.status === 'DELETED') return;
    try {
      await this.storage.delete(record.storagePath);
      await this.repository.markDeleted({ evidenceId: record.evidenceId, now });
    } catch (_) {
      await this.repository.markDeleteFailed({
        evidenceId: record.evidenceId,
        now,
        errorCode: 'storage-delete-failed',
      });
      console.warn('Task evidence deletion remains pending.', {
        evidenceId: record.evidenceId,
        errorCode: 'storage-delete-failed',
      });
      throw new TaskCampaignError('unavailable', 'Bukti belum dapat dihapus. Coba lagi.');
    }
  }
}

module.exports = {
  EVIDENCE_RETENTION_DAYS,
  MAX_CLEANUP_BATCH,
  MAX_IMAGE_INPUT_BYTES,
  MAX_IMAGE_OUTPUT_BYTES,
  TaskEvidenceService,
  buildStoragePath,
  decodeImageBase64,
  deriveEvidenceId,
  residentScopeHash,
  sanitizeEvidenceJpeg,
};
