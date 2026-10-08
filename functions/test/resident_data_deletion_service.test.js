const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { ResidentDataDeletionService } = require('../src/resident_data_deletion_service');

class FakeRepository {
  calls = [];
  async deleteResidentData(input) {
    this.calls.push(input);
    return { deleted: true };
  }
  async deleteOwnResidentData(input) {
    this.calls.push(input);
    return { deleted: true };
  }
}
const ID = 'a'.repeat(40);
const auth = { operatorUid: 'operator-a', signInProvider: 'password' };
const request = {
  residentId: ID,
  commandId: 'command-id-123456789012345678901234567890',
  residentRequestConfirmed: true,
  identityVerificationConfirmed: true,
};

test('same-device deletion is bound to the resident session and needs no operator identity attestation', async () => {
  const repo = new FakeRepository();
  const service = new ResidentDataDeletionService(repo, { clock: () => new Date(0) });
  const sessionToken = 'resident-session-token-012345678901234567890';
  const result = await service.deleteOwnResidentData({
    sessionToken,
    residentId: ID,
    communityId: 'rt-a',
  });
  assert.deepEqual(result, { deleted: true });
  assert.equal(repo.calls.length, 1);
  assert.equal(repo.calls[0].residentId, ID);
  assert.equal(repo.calls[0].rtId, 'rt-a');
  assert.equal(repo.calls[0].actorKind, 'RESIDENT_SELF');
  assert.equal(repo.calls[0].actorSessionHash,
    crypto.createHash('sha256').update(sessionToken).digest('hex'));
  assert.equal(repo.calls[0].residentRequestConfirmed, true);
  assert.equal(repo.calls[0].identityVerificationConfirmed, false);
  assert.equal(Object.hasOwn(repo.calls[0], 'sessionToken'), false);
  assert.equal(Object.hasOwn(repo.calls[0], 'operatorUid'), false);
  assert.equal(repo.calls[0].now.toISOString(), new Date(0).toISOString());
  await assert.rejects(
    service.deleteOwnResidentData({
      sessionToken,
      residentId: ID,
      communityId: 'rt-a',
      identityVerificationConfirmed: true,
    }),
    { code: 'invalid-argument' },
  );
  await assert.rejects(
    service.deleteOwnResidentData({
      sessionToken: 'not-a-session',
      residentId: ID,
      communityId: 'rt-a',
    }),
    { code: 'permission-denied' },
  );
  assert.equal(repo.calls.length, 1);
});

test('RT deletion requires an explicit resident request and offline identity check', async () => {
  const repo = new FakeRepository();
  const service = new ResidentDataDeletionService(repo, { clock: () => new Date(0) });
  await assert.rejects(
    service.deleteResidentData(auth, { ...request, residentRequestConfirmed: false }),
    { code: 'failed-precondition' },
  );
  await assert.rejects(
    service.deleteResidentData(auth, { ...request, identityVerificationConfirmed: false }),
    { code: 'failed-precondition' },
  );
  assert.equal(repo.calls.length, 0);
});

test('RT deletion accepts only same-RT password operator scope and minimal fields', async () => {
  const repo = new FakeRepository();
  const service = new ResidentDataDeletionService(repo, { clock: () => new Date(0) });
  await service.deleteResidentData(auth, request);
  assert.equal(repo.calls.length, 1);
  assert.equal(repo.calls[0].operatorUid, auth.operatorUid);
  assert.equal(repo.calls[0].residentId, ID);
  assert.equal(repo.calls[0].now.toISOString(), new Date(0).toISOString());
  await assert.rejects(
    service.deleteResidentData({ ...auth, signInProvider: 'anonymous' }, request),
    { code: 'permission-denied' },
  );
  await assert.rejects(
    service.deleteResidentData(auth, { ...request, rtId: 'rt-other' }),
    { code: 'invalid-argument' },
  );
});
