const test = require('node:test');
const assert = require('node:assert/strict');
const { FirestoreResidentSessionRepository } = require('../src/firestore_resident_session_repository');

test('FirestoreResidentSessionRepository tracks pendingTokenCleanups and cleans up old session tokens across retries', async () => {
  const store = new Map();
  const deletedTokenRefs = [];

  const fakeFirestore = {
    collection(name) {
      return {
        doc(id) {
          const docPath = `${name}/${id}`;
          return {
            id,
            path: docPath,
            async get() {
              const data = store.get(docPath);
              return {
                id,
                exists: data !== undefined,
                data: () => (data ? { ...data } : undefined),
              };
            },
          };
        },
        where(field, op, val) {
          return {
            limit(n) {
              return {
                async get() {
                  const matches = [];
                  for (const [p, d] of store.entries()) {
                    if (p.startsWith(`${name}/`) && d[field] === val) {
                      matches.push({
                        ref: { path: p },
                        id: p.split('/')[1],
                        data: () => ({ ...d }),
                      });
                    }
                  }
                  return {
                    empty: matches.length === 0,
                    docs: matches.slice(0, n),
                  };
                },
              };
            },
          };
        },
      };
    },
    batch() {
      const ops = [];
      return {
        delete(ref) {
          ops.push(ref);
        },
        async commit() {
          for (const ref of ops) {
            deletedTokenRefs.push(ref.path);
            store.delete(ref.path);
          }
        },
      };
    },
    async runTransaction(fn) {
      const transaction = {
        async get(ref) {
          const data = store.get(ref.path);
          return {
            id: ref.id,
            exists: data !== undefined,
            data: () => (data ? { ...data } : undefined),
          };
        },
        create(ref, data) {
          if (store.has(ref.path)) throw new Error('Document already exists: ' + ref.path);
          store.set(ref.path, { ...data });
        },
        update(ref, data) {
          const existing = store.get(ref.path) || {};
          store.set(ref.path, { ...existing, ...data });
        },
      };
      return fn(transaction);
    },
  };

  const repo = new FirestoreResidentSessionRepository(fakeFirestore);

  // Setup initial state: RT community, resident, session 1, enrollment
  store.set('rt_communities/rt-1', {
    joinCodeActive: true,
    joinCodeHash: 'code-hash',
  });
  store.set('resident_profiles/res-1', {
    rtId: 'rt-1',
    nickname: 'Budi',
    deletionPending: false,
  });
  store.set('resident_sessions/sess-1', {
    active: true,
    residentId: 'res-1',
    createdAt: new Date('2026-10-01'),
  });
  store.set('resident_enrollments/req-1', {
    rtId: 'rt-1',
    requestFingerprint: 'fp-1',
    residentId: 'res-1',
    sessionHash: 'sess-1',
    createdAt: new Date('2026-10-01'),
  });

  // Put a push token under sess-1
  store.set('resident_push_tokens/tok-1', {
    sessionIdHash: 'sess-1',
    token: 'fcm-tok-1',
    active: true,
  });

  // 1. Rotate session to sess-2, but simulate _deletePushTokensForSession throwing
  const originalDelete = repo._deletePushTokensForSession.bind(repo);
  let failDelete = true;
  repo._deletePushTokensForSession = async (sessId) => {
    if (failDelete) {
      throw new Error('Network error deleting push tokens');
    }
    return originalDelete(sessId);
  };

  const record2 = {
    communityId: 'rt-1',
    expectedJoinCodeHash: 'code-hash',
    requestHash: 'req-1',
    requestFingerprint: 'fp-1',
    residentId: 'res-1',
    sessionId: 'sess-2',
    resident: { nickname: 'Budi' },
    session: { active: true, createdAt: new Date('2026-10-02') },
  };

  await assert.rejects(repo.createResidentAndSession(record2), /Network error deleting push tokens/);

  // Assert transaction committed: session 2 exists, enrollment updated, and pendingTokenCleanups contains sess-1
  assert.equal(store.get('resident_sessions/sess-2').active, true);
  const enrollmentAfterFail = store.get('resident_enrollments/req-1');
  assert.equal(enrollmentAfterFail.sessionHash, 'sess-2');
  assert.deepEqual(enrollmentAfterFail.pendingTokenCleanups, ['sess-1']);
  assert.equal(store.has('resident_push_tokens/tok-1'), true);

  // 2. Retry: now deletion succeeds
  failDelete = false;
  const record3 = {
    ...record2,
    sessionId: 'sess-3',
    session: { active: true, createdAt: new Date('2026-10-03') },
  };

  const res3 = await repo.createResidentAndSession(record3);
  assert.equal(res3.residentId, 'res-1');

  // Verify token from sess-1 was deleted!
  assert.equal(store.has('resident_push_tokens/tok-1'), false);
  assert.ok(deletedTokenRefs.includes('resident_push_tokens/tok-1'));
});
