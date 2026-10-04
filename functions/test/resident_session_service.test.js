const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ResidentSessionService,
  SESSION_TTL_MS,
  hashJoinCode,
  hashSessionToken,
  normalizeJoinCode,
} = require('../src/resident_session_service');
const { residentCallableOptions } = require('../src/callable_options');

const NOW = new Date('2026-10-04T12:00:00.000Z');
const JOIN_CODE = 'ABCD2345EFGH';
const enrollmentRequestId = (suffix = '1') =>
  `request-${suffix.replace(/[^A-Za-z0-9_-]/g, '_').padEnd(40, 'x')}`;

class FakeRepository {
  constructor() {
    this.communities = new Map([
      ['rt-a', {
        id: 'rt-a',
        displayName: 'Komunitas Percontohan',
        rtLabel: 'RT 01',
        joinCodeHash: hashJoinCode(JOIN_CODE),
        joinCodeActive: true,
      }],
    ]);
    this.sessions = new Map();
    this.residents = new Map();
    this.enrollments = new Map();
  }

  async findCommunityByJoinCodeHash(hash) {
    return [...this.communities.values()].find((item) =>
      item.joinCodeActive && item.joinCodeHash === hash) ?? null;
  }

  async createResidentAndSession(record) {
    const community = this.communities.get(record.communityId);
    if (!community || !community.joinCodeActive ||
        community.joinCodeHash !== record.expectedJoinCodeHash) {
      throw new Error('join code changed');
    }
    if (this.sessions.has(record.sessionId)) throw new Error('session collision');
    const existing = this.enrollments.get(record.requestHash);
    if (existing) {
      if (existing.rtId !== record.communityId ||
          existing.requestFingerprint !== record.requestFingerprint) {
        const error = new Error('enrollment request mismatch');
        error.code = 'permission-denied';
        throw error;
      }
      const previous = this.sessions.get(existing.sessionHash);
      if (previous?.active === true) {
        previous.active = false;
        previous.revokedAt = record.session.createdAt;
      }
      const replacement = structuredClone(record.session);
      replacement.residentId = existing.residentId;
      this.sessions.set(record.sessionId, replacement);
      existing.sessionHash = record.sessionId;
      existing.updatedAt = record.session.createdAt;
      return { residentId: existing.residentId };
    }
    this.residents.set(record.residentId, structuredClone(record.resident));
    this.sessions.set(record.sessionId, structuredClone(record.session));
    this.enrollments.set(record.requestHash, {
      rtId: record.communityId,
      requestFingerprint: record.requestFingerprint,
      residentId: record.residentId,
      sessionHash: record.sessionId,
    });
    return { residentId: record.residentId };
  }

  async getSession(id) {
    return structuredClone(this.sessions.get(id) ?? null);
  }

  async getResident(id) {
    return structuredClone(this.residents.get(id) ?? null);
  }

  async getCommunity(id) {
    return structuredClone(this.communities.get(id) ?? null);
  }

  async revokeSession(id, revokedAt) {
    const session = this.sessions.get(id);
    if (!session) return;
    session.active = false;
    session.revokedAt = revokedAt;
  }
}

function setup() {
  const repository = new FakeRepository();
  let id = 0;
  const service = new ResidentSessionService(repository, {
    clock: () => new Date(NOW),
    tokenFactory: () => `opaque-session-token-${++id}-not-a-real-credential`,
    idFactory: () => `generated-id-${++id}`,
  });
  return { repository, service };
}

test('normalizes code only for lookup and requires a high-entropy shape', () => {
  assert.equal(normalizeJoinCode(' abcd2345efgh '), JOIN_CODE);
  assert.throws(() => normalizeJoinCode('SHORT'), { code: 'permission-denied' });
  assert.throws(() => normalizeJoinCode('ABCD-2345-EFGH'), { code: 'permission-denied' });
});

test('creates a scoped minimal profile and stores only a token hash', async () => {
  const { repository, service } = setup();
  const session = await service.createSession({
    joinCode: JOIN_CODE.toLowerCase(),
    nickname: '  Rani  ',
    requestId: enrollmentRequestId('basic'),
  });

  assert.equal(session.communityId, 'rt-a');
  assert.equal(session.rtLabel, 'RT 01');
  assert.equal(session.nickname, 'Rani');
  assert.ok(session.sessionToken.startsWith('opaque-session-token-'));
  assert.equal(session.expiresAt.getTime(), NOW.getTime() + SESSION_TTL_MS);
  assert.equal(repository.sessions.size, 1);
  assert.equal(repository.residents.size, 1);

  const [storedTokenHash] = repository.sessions.keys();
  assert.ok(/^[a-f0-9]{64}$/.test(storedTokenHash));
  assert.notEqual(storedTokenHash, session.sessionToken);
  const [storedResident] = repository.residents.values();
  assert.deepEqual(Object.keys(storedResident).sort(), [
    'createdAt', 'createdBy', 'needsAssistance', 'nickname', 'rtId', 'updatedAt',
  ]);
  assert.equal(storedResident.nickname, 'Rani');
});

test('unknown, disabled, and malformed codes return the same generic failure', async () => {
  const { repository, service } = setup();
  const errors = [];
  for (const joinCode of ['ZZZZ2345EFGH', 'SHORT', '']) {
    try {
      await service.createSession({
        joinCode,
        nickname: 'Warga',
        requestId: enrollmentRequestId(joinCode || 'empty'),
      });
      assert.fail('expected access denial');
    } catch (error) {
      errors.push({ code: error.code, message: error.message });
    }
  }
  repository.communities.get('rt-a').joinCodeActive = false;
  try {
    await service.createSession({
      joinCode: JOIN_CODE,
      nickname: 'Warga',
      requestId: enrollmentRequestId('disabled'),
    });
    assert.fail('expected access denial');
  } catch (error) {
    errors.push({ code: error.code, message: error.message });
  }
  assert.deepEqual(new Set(errors.map((error) => error.code)), new Set(['permission-denied']));
  assert.deepEqual(new Set(errors.map((error) => error.message)), new Set([
    'Kode RT tidak valid atau tidak aktif.',
  ]));
});

test('rejects empty or oversized nickname without storing a profile', async () => {
  const { repository, service } = setup();
  for (const nickname of ['', '   ', 'x'.repeat(41)]) {
    await assert.rejects(service.createSession({
      joinCode: JOIN_CODE,
      nickname,
      requestId: enrollmentRequestId(nickname || 'empty'),
    }), {
      code: 'invalid-argument',
    });
  }
  assert.equal(repository.residents.size, 0);
});

test('malformed enrollment request ids are rejected before profile creation', async () => {
  const { repository, service } = setup();
  await assert.rejects(service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Rani',
    requestId: 'short',
  }), { code: 'invalid-argument' });
  assert.equal(repository.residents.size, 0);
  assert.equal(repository.sessions.size, 0);
});

test('session validation is scoped, expires, and can be revoked idempotently', async () => {
  const { repository, service } = setup();
  const created = await service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Dewi',
    requestId: enrollmentRequestId('dewi'),
  });
  const restored = await service.validateSession(created.sessionToken);
  assert.equal(restored.residentId, created.residentId);
  assert.equal(restored.communityId, 'rt-a');
  assert.equal(restored.nickname, 'Dewi');

  await service.revokeSession(created.sessionToken);
  await service.revokeSession(created.sessionToken);
  await assert.rejects(service.validateSession(created.sessionToken), {
    code: 'permission-denied',
  });

  const other = setup();
  const expiring = await other.service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Ayu',
    requestId: enrollmentRequestId('ayu'),
  });
  other.repository.sessions.get(
    [...other.repository.sessions.keys()][0],
  ).expiresAt = new Date(NOW.getTime() - 1);
  await assert.rejects(other.service.validateSession(expiring.sessionToken), {
    code: 'permission-denied',
  });
});


test('enrollment retries reuse one resident and rotate the opaque session token', async () => {
  const { repository, service } = setup();
  const requestId = enrollmentRequestId('retry');
  const first = await service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Mira',
    requestId,
  });
  const retry = await service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Mira',
    requestId,
  });

  assert.equal(retry.residentId, first.residentId);
  assert.notEqual(retry.sessionToken, first.sessionToken);
  assert.equal(repository.residents.size, 1);
  assert.equal(repository.enrollments.size, 1);
  assert.equal(repository.sessions.size, 2);
  assert.equal(repository.sessions.get(hashSessionToken(first.sessionToken)).active, false);
  assert.equal(repository.sessions.get(hashSessionToken(retry.sessionToken)).active, true);
  assert.equal((await service.validateSession(retry.sessionToken)).residentId, first.residentId);
  await assert.rejects(service.validateSession(first.sessionToken), { code: 'permission-denied' });
  await assert.rejects(service.createSession({
    joinCode: JOIN_CODE,
    nickname: 'Other nickname',
    requestId,
  }), { code: 'permission-denied' });
});

test('resident callables require App Check except in a demo emulator project', () => {
  assert.equal(residentCallableOptions({}).enforceAppCheck, true);
  assert.equal(residentCallableOptions({
    FUNCTIONS_EMULATOR: 'true',
    GCLOUD_PROJECT: 'demo-guyub-functions',
  }).enforceAppCheck, false);
  assert.equal(residentCallableOptions({
    FUNCTIONS_EMULATOR: 'true',
    GCLOUD_PROJECT: 'guyub-production',
  }).enforceAppCheck, true);
  assert.equal(residentCallableOptions({
    FUNCTIONS_EMULATOR: 'false',
    GCLOUD_PROJECT: 'demo-guyub-functions',
  }).enforceAppCheck, true);
  assert.equal(residentCallableOptions({
    FUNCTIONS_EMULATOR: 'true',
    GCLOUD_PROJECT: 'demo-guyub-functions',
  }).region, 'asia-southeast2');
});
