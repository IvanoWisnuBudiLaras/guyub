const test = require('node:test');
const assert = require('node:assert/strict');
const {
  FirestoreResidentDataDeletionRepository,
} = require('../src/firestore_resident_data_deletion_repository');
const { buildStoragePath, residentScopeHash } = require('../src/task_evidence_service');

const RT_ID = 'rt-a';
const RESIDENT_ID = 'a'.repeat(40);
const TASK_ID = 'b'.repeat(40);
const EVIDENCE_ID = 'c'.repeat(40);

function evidenceRepository(record, storage) {
  let removed = false;
  let batchCommits = 0;
  const document = { id: EVIDENCE_ID, data: () => record, ref: { id: EVIDENCE_ID } };
  const firestore = {
    collection(name) {
      assert.equal(name, 'task_evidence');
      return {
        where(field, operator, value) {
          assert.equal(field, 'residentScopeHash');
          assert.equal(operator, '==');
          assert.equal(value, residentScopeHash(RT_ID, RESIDENT_ID));
          return { limit: () => ({
            get: async () => removed
              ? { empty: true, docs: [] }
              : { empty: false, docs: [document] },
          }) };
        },
      };
    },
    batch() {
      return {
        delete() {},
        commit: async () => { removed = true; batchCommits += 1; },
      };
    },
  };
  return {
    repository: new FirestoreResidentDataDeletionRepository(firestore, storage),
    wasRemoved: () => removed,
    batchCommits: () => batchCommits,
  };
}

test('failed evidence-object deletion keeps metadata available for retry', async () => {
  const storagePath = buildStoragePath(RT_ID, TASK_ID, RESIDENT_ID, EVIDENCE_ID);
  const record = {
    evidenceId: EVIDENCE_ID,
    residentScopeHash: residentScopeHash(RT_ID, RESIDENT_ID),
    storagePath,
    status: 'READY',
  };
  let attempts = 0;
  const storage = {
    async delete(path) {
      assert.equal(path, storagePath);
      attempts += 1;
      if (attempts === 1) throw new Error('temporary storage failure');
    },
  };
  const testState = evidenceRepository(record, storage);
  await assert.rejects(
    testState.repository._deleteEvidence({ residentId: RESIDENT_ID }, RT_ID),
    { code: 'unavailable' },
  );
  assert.equal(testState.wasRemoved(), false);
  assert.equal(testState.batchCommits(), 0);
  await testState.repository._deleteEvidence({ residentId: RESIDENT_ID }, RT_ID);
  assert.equal(attempts, 2);
  assert.equal(testState.wasRemoved(), true);
  assert.equal(testState.batchCommits(), 1);
});
