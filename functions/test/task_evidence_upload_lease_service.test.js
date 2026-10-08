const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {
  FirestoreTaskEvidenceRepository,
} = require('../src/firestore_task_evidence_repository');
const {
  TaskEvidenceService,
  buildStoragePath,
  deriveEvidenceId,
  residentScopeHash,
} = require('../src/task_evidence_service');
const {
  UPLOAD_LEASE_MS,
  UPLOAD_TIMEOUT_SECONDS,
} = require('../src/task_evidence_upload_lease');
const { hashSessionToken } = require('../src/resident_session_service');
const { responseDocumentId } = require('../src/task_response_service');

const RT_ID = 'rt-upload-race';
const RESIDENT_ID = 'a'.repeat(40);
const TASK_ID = 'b'.repeat(40);
const SESSION_TOKEN = 'session-token-for-upload-race-123456';
const UPLOAD_REQUEST_ID = 'u'.repeat(40);
const DELETE_COMMAND_ID = 'd'.repeat(40);

class MemoryFirestore {
  constructor() { this.documents = new Map(); }

  collection(collectionName) {
    return {
      doc: (id) => ({ collectionName, id }),
    };
  }

  put(collectionName, id, value) {
    this.documents.set(`${collectionName}/${id}`, structuredClone(value));
  }

  read(collectionName, id) {
    const value = this.documents.get(`${collectionName}/${id}`);
    return value === undefined ? undefined : structuredClone(value);
  }

  async runTransaction(work) {
    const transaction = {
      get: async (ref) => {
        const value = this.documents.get(`${ref.collectionName}/${ref.id}`);
        return {
          id: ref.id,
          exists: value !== undefined,
          ref,
          data: () => value === undefined ? undefined : structuredClone(value),
        };
      },
      create: (ref, value) => {
        const key = `${ref.collectionName}/${ref.id}`;
        if (this.documents.has(key)) throw new Error('already exists');
        this.documents.set(key, structuredClone(value));
      },
      update: (ref, updates) => {
        const key = `${ref.collectionName}/${ref.id}`;
        const current = this.documents.get(key);
        if (!current) throw new Error('missing document');
        for (const [field, value] of Object.entries(updates)) {
          if (value?.constructor?.name === 'DeleteTransform') delete current[field];
          else current[field] = value;
        }
      },
    };
    return work(transaction);
  }
}

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

test('resident deletion waits for an in-flight upload and failed cleanup remains retryable', async () => {
  const firestore = new MemoryFirestore();
  const sessionIdHash = hashSessionToken(SESSION_TOKEN);
  const responseId = responseDocumentId(RT_ID, TASK_ID, RESIDENT_ID);
  const now = new Date('2026-10-06T12:00:00.000Z');
  firestore.put('resident_sessions', sessionIdHash, {
    residentId: RESIDENT_ID, rtId: RT_ID, active: true,
    expiresAt: new Date(now.getTime() + 60_000),
  });
  firestore.put('resident_profiles', RESIDENT_ID, {
    residentId: RESIDENT_ID, rtId: RT_ID, nickname: 'Warga A',
  });
  firestore.put('rt_communities', RT_ID, { rtId: RT_ID });
  firestore.put('task_campaigns', TASK_ID, {
    campaignId: TASK_ID, rtId: RT_ID, status: 'ACTIVE',
  });
  firestore.put('task_responses', responseId, {
    responseId, taskId: TASK_ID, rtId: RT_ID, residentId: RESIDENT_ID,
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });

  const saveStarted = deferred();
  const finishSave = deferred();
  const objects = new Map();
  let deleteAttempts = 0;
  let failDeleteOnce = false;
  const storage = {
    assertConfigured() {},
    async save(path, bytes) {
      saveStarted.resolve();
      await finishSave.promise;
      objects.set(path, Buffer.from(bytes));
    },
    async delete(path) {
      deleteAttempts += 1;
      if (failDeleteOnce) {
        failDeleteOnce = false;
        throw new Error('temporary object deletion failure');
      }
      objects.delete(path);
    },
  };
  const service = new TaskEvidenceService(
    new FirestoreTaskEvidenceRepository(firestore),
    { async validateSession() { return { communityId: RT_ID, residentId: RESIDENT_ID }; } },
    storage,
    { clock: () => now, sanitizeImage: async (bytes) => bytes },
  );
  const uploadPromise = service.uploadResidentEvidence({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    requestId: UPLOAD_REQUEST_ID,
    imageBase64: Buffer.from('synthetic image bytes').toString('base64'),
  });

  await saveStarted.promise;
  const commandHash = crypto.createHash('sha256').update(UPLOAD_REQUEST_ID).digest('hex');
  const evidenceId = deriveEvidenceId(RT_ID, RESIDENT_ID, TASK_ID, commandHash);
  const evidenceBeforeDelete = firestore.read('task_evidence', evidenceId);
  assert.equal(evidenceBeforeDelete.status, 'UPLOADING');
  assert.ok(evidenceBeforeDelete.uploadLeaseUntil > now);
  try {
    await assert.rejects(service.deleteResidentEvidence({
      sessionToken: SESSION_TOKEN,
      evidenceId,
      commandId: DELETE_COMMAND_ID,
    }), { code: 'failed-precondition' });
  } finally {
    finishSave.resolve();
  }
  assert.equal(deleteAttempts, 0);
  const uploaded = await uploadPromise;
  const readyRecord = firestore.read('task_evidence', evidenceId);
  assert.equal(readyRecord.status, 'READY');
  assert.equal(readyRecord.uploadLeaseUntil, undefined);
  const storagePath = readyRecord.storagePath;
  assert.equal(objects.has(storagePath), true);

  failDeleteOnce = true;
  await assert.rejects(service.deleteResidentEvidence({
    sessionToken: SESSION_TOKEN,
    evidenceId: uploaded.evidenceId,
    commandId: DELETE_COMMAND_ID,
  }), { code: 'unavailable' });
  const pendingRecord = firestore.read('task_evidence', evidenceId);
  assert.equal(pendingRecord.status, 'DELETE_PENDING');
  assert.equal(pendingRecord.storagePath, storagePath);
  assert.equal(objects.has(storagePath), true);

  const deleted = await service.deleteResidentEvidence({
    sessionToken: SESSION_TOKEN,
    evidenceId: uploaded.evidenceId,
    commandId: DELETE_COMMAND_ID,
  });
  assert.deepEqual(deleted, { deleted: true });
  assert.equal(deleteAttempts, 2);
  assert.equal(objects.has(storagePath), false);
  const finalRecord = firestore.read('task_evidence', evidenceId);
  assert.equal(finalRecord.status, 'DELETED');
  assert.equal(finalRecord.storagePath, undefined);
});


test('expiry cleanup defers after a near-expiry upload retry renews the lease', async () => {
  assert.ok(UPLOAD_LEASE_MS > UPLOAD_TIMEOUT_SECONDS * 1000);
  const firestore = new MemoryFirestore();
  const repository = new FirestoreTaskEvidenceRepository(firestore);
  const sessionIdHash = hashSessionToken(SESSION_TOKEN);
  const responseId = responseDocumentId(RT_ID, TASK_ID, RESIDENT_ID);
  const now = new Date('2026-10-06T12:00:00.000Z');
  const expiresAt = new Date(now.getTime() + 1000);
  const createdAt = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const uploadLeaseUntil = new Date(now.getTime() - 1000);
  firestore.put('resident_sessions', sessionIdHash, {
    residentId: RESIDENT_ID, rtId: RT_ID, active: true,
    expiresAt: new Date(now.getTime() + 60_000),
  });
  firestore.put('resident_profiles', RESIDENT_ID, {
    residentId: RESIDENT_ID, rtId: RT_ID, nickname: 'Warga A',
  });
  firestore.put('rt_communities', RT_ID, { rtId: RT_ID });
  firestore.put('task_campaigns', TASK_ID, {
    campaignId: TASK_ID, rtId: RT_ID, status: 'ACTIVE',
  });
  firestore.put('task_responses', responseId, {
    responseId, taskId: TASK_ID, rtId: RT_ID, residentId: RESIDENT_ID,
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });

  const imageBytes = Buffer.from('near-expiry upload retry');
  const commandHash = crypto.createHash('sha256').update(UPLOAD_REQUEST_ID).digest('hex');
  const contentHash = crypto.createHash('sha256').update(imageBytes).digest('hex');
  const evidenceId = deriveEvidenceId(RT_ID, RESIDENT_ID, TASK_ID, commandHash);
  const storagePath = buildStoragePath(RT_ID, TASK_ID, RESIDENT_ID, evidenceId);
  const scopeHash = residentScopeHash(RT_ID, RESIDENT_ID);
  firestore.put('task_evidence', evidenceId, {
    evidenceId, rtId: RT_ID, taskId: TASK_ID, responseId,
    residentScopeHash: scopeHash, commandHash, contentHash, storagePath,
    status: 'UPLOADING', createdAt, expiresAt, uploadLeaseUntil,
    deletionCommandHash: null, deleteAttemptCount: 0,
  });

  await repository.reserveUpload({
    evidenceId, rtId: RT_ID, residentId: RESIDENT_ID,
    residentScopeHash: scopeHash, sessionIdHash, taskId: TASK_ID,
    commandHash, contentHash, storagePath, now, expiresAt,
    uploadLeaseUntil: new Date(now.getTime() + UPLOAD_LEASE_MS),
  });
  const retriedRecord = firestore.read('task_evidence', evidenceId);
  assert.equal(retriedRecord.uploadLeaseUntil.getTime(), now.getTime() + UPLOAD_LEASE_MS);

  const justExpired = new Date(expiresAt.getTime() + 1000);
  assert.equal(await repository.beginExpiredDeletion({ evidenceId, now: justExpired }), null);
  assert.equal(firestore.read('task_evidence', evidenceId).status, 'UPLOADING');

  // A pre-fix scheduled run could already have changed the state but preserved the live lease.
  firestore.documents.get(`task_evidence/${evidenceId}`).status = 'DELETE_PENDING';
  await repository.markDeleteFailed({
    evidenceId, now: justExpired, errorCode: 'storage-delete-failed',
  });
  const failedLegacyCleanup = firestore.read('task_evidence', evidenceId);
  assert.equal(failedLegacyCleanup.uploadLeaseUntil.getTime(), now.getTime() + UPLOAD_LEASE_MS);
  assert.equal(await repository.beginExpiredDeletion({ evidenceId, now: justExpired }), null);
  assert.equal(firestore.read('task_evidence', evidenceId).status, 'DELETE_PENDING');
});
