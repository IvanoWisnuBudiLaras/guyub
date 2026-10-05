const test = require('node:test');
const assert = require('node:assert/strict');
const { ResidentDataDeletionService } = require('../src/resident_data_deletion_service');

class FakeRepository {
  calls = [];
  async deleteResidentData(input) {
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
