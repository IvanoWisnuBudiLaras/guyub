const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const {
  TaskEvidenceService,
  sanitizeEvidenceJpeg,
} = require('../src/task_evidence_service');
const { hashSessionToken } = require('../src/resident_session_service');

const SESSION_TOKEN = 'resident-evidence-session-token-0001';
const TASK_ID = 'a'.repeat(40);
const REQUEST_ID = 'e'.repeat(40);
const DELETE_COMMAND_ID = 'd'.repeat(40);
const RT_ID = 'rt-evidence-test';
const RESIDENT_ID = 'resident-evidence-test';
const NOW = new Date('2026-10-05T12:00:00.000Z');
const JPEG = fs.readFileSync(path.join(__dirname, 'fixtures', 'geotagged.jpg'));

class FakeSessions {
  async validateSession(token) {
    if (token !== SESSION_TOKEN) throw Object.assign(new Error('denied'), { code: 'permission-denied' });
    return { residentId: RESIDENT_ID, communityId: RT_ID };
  }
}

class FakeRepository {
  constructor() {
    this.calls = [];
    this.records = new Map();
    this.markReadyError = null;
    this.markReadyErrorAfterCommit = null;
  }

  async reserveUpload(input) {
    this.calls.push(['reserveUpload', input]);
    const existing = this.records.get(input.evidenceId);
    if (existing) {
      if (existing.contentHash !== input.contentHash ||
          existing.commandHash !== input.commandHash ||
          existing.residentScopeHash !== input.residentScopeHash) {
        throw Object.assign(new Error('conflict'), { code: 'failed-precondition' });
      }
      return { ...existing };
    }
    const record = {
      ...input,
      status: 'UPLOADING',
    };
    this.records.set(input.evidenceId, record);
    return { ...record };
  }

  async markReady(input) {
    this.calls.push(['markReady', input]);
    const record = this.records.get(input.evidenceId);
    if (this.markReadyError) {
      const error = this.markReadyError;
      this.markReadyError = null;
      throw error;
    }
    record.status = 'READY';
    if (this.markReadyErrorAfterCommit) {
      const error = this.markReadyErrorAfterCommit;
      this.markReadyErrorAfterCommit = null;
      throw error;
    }
    return { ...record };
  }

  async getForOperator(input) {
    this.calls.push(['getForOperator', input]);
    const record = this.records.get(input.evidenceId);
    if (!record || record.status !== 'READY') {
      throw Object.assign(new Error('denied'), { code: 'permission-denied' });
    }
    return { ...record };
  }

  async requestResidentDeletion(input) {
    this.calls.push(['requestResidentDeletion', input]);
    const record = this.records.get(input.evidenceId);
    if (!record || record.residentScopeHash !== input.residentScopeHash || record.rtId !== input.rtId) {
      throw Object.assign(new Error('denied'), { code: 'permission-denied' });
    }
    if (record.status !== 'DELETED') record.status = 'DELETE_PENDING';
    return { ...record };
  }

  async listDueEvidence(input) {
    this.calls.push(['listDueEvidence', input]);
    let all = [...this.records.values()];
    if (input.startAfterEvidenceId) {
      const idx = all.findIndex((r) => r.evidenceId === input.startAfterEvidenceId);
      if (idx >= 0) all = all.slice(idx + 1);
    }
    all = all.filter((record) => record.expiresAt <= input.now && record.status !== 'DELETED');
    if (input.limit) all = all.slice(0, input.limit);
    return all.map((record) => ({ ...record }));
  }

  async beginExpiredDeletion(input) {
    this.calls.push(['beginExpiredDeletion', input]);
    const record = this.records.get(input.evidenceId);
    if (!record || record.expiresAt > input.now || record.status === 'DELETED') return null;
    record.status = 'DELETE_PENDING';
    return { ...record };
  }

  async markDeleted(input) {
    this.calls.push(['markDeleted', input]);
    const record = this.records.get(input.evidenceId);
    record.status = 'DELETED';
  }

  async markDeleteFailed(input) {
    this.calls.push(['markDeleteFailed', input]);
    const record = this.records.get(input.evidenceId);
    record.status = 'DELETE_PENDING';
    record.deleteAttemptCount = (record.deleteAttemptCount ?? 0) + 1;
  }
}

class FakeStorage {
  constructor() {
    this.objects = new Map();
    this.saveCalls = [];
    this.deleteCalls = [];
    this.deleteError = null;
    this.configError = null;
  }

  assertConfigured() {
    if (this.configError) throw this.configError;
  }

  async save(storagePath, bytes, metadata) {
    this.saveCalls.push({ storagePath, bytes: Buffer.from(bytes), metadata });
    this.objects.set(storagePath, Buffer.from(bytes));
  }

  async read(storagePath) {
    const bytes = this.objects.get(storagePath);
    if (!bytes) throw new Error('not found');
    return Buffer.from(bytes);
  }

  async delete(storagePath) {
    this.deleteCalls.push(storagePath);
    if (this.deleteError) throw this.deleteError;
    this.objects.delete(storagePath);
  }
}

function createService(repository = new FakeRepository(), storage = new FakeStorage()) {
  return {
    repository,
    storage,
    service: new TaskEvidenceService(repository, new FakeSessions(), storage, {
      clock: () => new Date(NOW),
    }),
  };
}

function uploadRequest(overrides = {}) {
  return {
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    requestId: REQUEST_ID,
    imageBase64: JPEG.toString('base64'),
    ...overrides,
  };
}

test('server re-encodes a geotagged JPEG and removes EXIF before persistence', async () => {
  const sourceMetadata = await sharp(JPEG).metadata();
  assert.ok(sourceMetadata.exif);
  const sanitized = await sanitizeEvidenceJpeg(JPEG);
  const storedMetadata = await sharp(sanitized).metadata();
  assert.equal(storedMetadata.format, 'jpeg');
  assert.equal(storedMetadata.exif, undefined);
  assert.equal(storedMetadata.iptc, undefined);
  assert.equal(storedMetadata.xmp, undefined);
  assert.equal(storedMetadata.width <= 1280, true);
  assert.equal(storedMetadata.height <= 1280, true);
});

test('upload is scoped to joined resident task, stores a private object, and replays idempotently', async () => {
  const { repository, storage, service } = createService();
  const first = await service.uploadResidentEvidence(uploadRequest());
  const replay = await service.uploadResidentEvidence(uploadRequest());

  assert.equal(first.evidenceId, replay.evidenceId);
  assert.equal(first.expiresAt, '2026-11-04T12:00:00.000Z');
  assert.equal(repository.calls[0][1].sessionIdHash, hashSessionToken(SESSION_TOKEN));
  assert.equal(repository.calls[0][1].residentId, RESIDENT_ID);
  assert.equal(repository.calls[0][1].rtId, RT_ID);
  assert.equal(repository.calls[0][1].taskId, TASK_ID);
  assert.equal(repository.calls[0][1].expiresAt.toISOString(), first.expiresAt);
  assert.equal(storage.saveCalls.length, 1);
  assert.equal(storage.objects.size, 1);
  const saved = storage.saveCalls[0];
  assert.match(saved.storagePath, /^evidence\/[a-f0-9]{20}\/[a-f0-9]{40}\/[a-f0-9]{40}\.jpg$/u);
  assert.deepEqual(saved.metadata, {
    contentType: 'image/jpeg',
    cacheControl: 'private, no-store',
    evidenceId: first.evidenceId,
  });
  assert.equal((await sharp(saved.bytes).metadata()).exif, undefined);
  assert.equal(JSON.stringify(first).includes('https://'), false);
  assert.equal(JSON.stringify(first).includes(SESSION_TOKEN), false);
});

test('upload retries reconcile uncertain Firestore readiness without deleting a committed object', async () => {
  const repository = new FakeRepository();
  const storage = new FakeStorage();
  const { service } = createService(repository, storage);
  repository.markReadyErrorAfterCommit = new Error('transaction reply lost');

  await assert.rejects(service.uploadResidentEvidence(uploadRequest()), {
    code: 'unavailable',
  });
  assert.equal([...repository.records.values()][0].status, 'READY');
  assert.equal(storage.objects.size, 1);
  const retry = await service.uploadResidentEvidence(uploadRequest());
  assert.equal(retry.evidenceId, [...repository.records.keys()][0]);
  assert.equal(storage.objects.size, 1);
  assert.equal(storage.saveCalls.length, 1);

  const pendingRepository = new FakeRepository();
  const pendingStorage = new FakeStorage();
  const pending = createService(pendingRepository, pendingStorage);
  pendingRepository.markReadyError = new Error('transaction unavailable');
  await assert.rejects(pending.service.uploadResidentEvidence(uploadRequest()), {
    code: 'unavailable',
  });
  assert.equal([...pendingRepository.records.values()][0].status, 'UPLOADING');
  assert.equal(pendingStorage.objects.size, 1);
  await pending.service.uploadResidentEvidence(uploadRequest());
  assert.equal([...pendingRepository.records.values()][0].status, 'READY');
  assert.equal(pendingStorage.saveCalls.length, 2);
});

test('missing bucket configuration fails before creating an evidence record', async () => {
  const repository = new FakeRepository();
  const storage = new FakeStorage();
  storage.configError = Object.assign(new Error('not configured'), {
    code: 'failed-precondition',
  });
  const { service } = createService(repository, storage);
  await assert.rejects(service.uploadResidentEvidence(uploadRequest()), {
    code: 'failed-precondition',
  });
  assert.equal(repository.calls.length, 0);
  assert.equal(storage.saveCalls.length, 0);
});

test('invalid image and forged scope are rejected before object storage', async () => {
  const { storage, service } = createService();
  await assert.rejects(
    service.uploadResidentEvidence(uploadRequest({ imageBase64: 'bm90LWEtanBlZw==' })),
    { code: 'invalid-argument' },
  );
  await assert.rejects(
    service.uploadResidentEvidence(uploadRequest({ rtId: 'rt-other' })),
    { code: 'invalid-argument' },
  );
  assert.equal(storage.saveCalls.length, 0);
});

test('only a password-authenticated RT operator can read the private evidence bytes', async () => {
  const { service } = createService();
  const uploaded = await service.uploadResidentEvidence(uploadRequest());
  const result = await service.getEvidenceForOperator({
    operatorUid: 'operator-a',
    signInProvider: 'password',
  }, { evidenceId: uploaded.evidenceId });
  assert.equal(result.evidenceId, uploaded.evidenceId);
  assert.equal(result.contentType, 'image/jpeg');
  assert.equal((await sharp(Buffer.from(result.imageBase64, 'base64')).metadata()).exif, undefined);
  await assert.rejects(service.getEvidenceForOperator({
    operatorUid: 'operator-a',
    signInProvider: 'anonymous',
  }, { evidenceId: uploaded.evidenceId }), { code: 'permission-denied' });
});

test('resident deletion is scoped and physically removes storage idempotently', async () => {
  const { repository, storage, service } = createService();
  const uploaded = await service.uploadResidentEvidence(uploadRequest());
  const storagePath = [...storage.objects.keys()][0];
  const result = await service.deleteResidentEvidence({
    sessionToken: SESSION_TOKEN,
    evidenceId: uploaded.evidenceId,
    commandId: DELETE_COMMAND_ID,
  });
  const replay = await service.deleteResidentEvidence({
    sessionToken: SESSION_TOKEN,
    evidenceId: uploaded.evidenceId,
    commandId: DELETE_COMMAND_ID,
  });

  assert.deepEqual(result, { deleted: true });
  assert.deepEqual(replay, { deleted: true });
  assert.equal(storage.objects.has(storagePath), false);
  assert.equal(storage.deleteCalls.length, 1);
  assert.equal(repository.records.get(uploaded.evidenceId).status, 'DELETED');
});

test('retention cleanup physically deletes expired objects and retries failures', async () => {
  const repository = new FakeRepository();
  const storage = new FakeStorage();
  const { service } = createService(repository, storage);
  const uploaded = await service.uploadResidentEvidence(uploadRequest());
  const storagePath = [...storage.objects.keys()][0];
  const later = new Date('2026-11-05T12:00:00.000Z');
  const cleanup = await service.deleteExpiredEvidence({ now: later });

  assert.deepEqual(cleanup, { examined: 1, deleted: 1, retryPending: 0 });
  assert.equal(storage.objects.has(storagePath), false);
  assert.equal(repository.records.get(uploaded.evidenceId).status, 'DELETED');

  const pending = await service.uploadResidentEvidence(uploadRequest({ requestId: 'f'.repeat(40) }));
  const pendingPath = [...storage.objects.keys()].find((item) => item.includes(pending.evidenceId));
  storage.deleteError = new Error('storage unavailable');
  const failed = await service.deleteExpiredEvidence({ now: later });
  assert.deepEqual(failed, { examined: 1, deleted: 0, retryPending: 1 });
  assert.equal(storage.objects.has(pendingPath), true);
  assert.equal(repository.records.get(pending.evidenceId).status, 'DELETE_PENDING');
});

test('retention cleanup paginates across batches and prevents starvation when items fail', async () => {
  const repository = new FakeRepository();
  const storage = new FakeStorage();
  const { service } = createService(repository, storage);

  const later = new Date('2026-11-05T12:00:00.000Z');
  const past = new Date('2026-10-01T12:00:00.000Z');
  for (let i = 0; i < 125; i += 1) {
    const id = `evi-${String(i).padStart(4, '0')}`;
    const storagePath = `evidence/test/${id}.jpg`;
    storage.objects.set(storagePath, Buffer.from('test'));
    repository.records.set(id, {
      evidenceId: id,
      storagePath,
      status: 'READY',
      expiresAt: past,
      uploadLeaseUntil: null,
    });
  }

  const failingPath = 'evidence/test/evi-0000.jpg';
  const originalDelete = storage.delete.bind(storage);
  storage.delete = async (p) => {
    if (p === failingPath) throw new Error('Simulated failure on first item');
    return originalDelete(p);
  };

  const cleanup = await service.deleteExpiredEvidence({ now: later, batchSize: 50 });
  assert.equal(cleanup.examined, 125);
  assert.equal(cleanup.deleted, 124);
  assert.equal(cleanup.retryPending, 1);
  assert.equal(repository.records.get('evi-0000').status, 'DELETE_PENDING');
  assert.equal(repository.records.get('evi-0124').status, 'DELETED');
});
