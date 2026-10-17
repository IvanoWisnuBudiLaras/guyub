// Prototype test: does the HTTP adapter reach the same service layer as the
// Cloud Functions adapter? Run against the Firebase emulator suite.
//
//   npx firebase-tools emulators:exec --project demo-guyub-functions \
//     --only auth,firestore,storage \
//     "node --test functions/test/http_adapter_seam.test.js"

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { callableNames } = require('../src/app');

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'demo-guyub-functions';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, firestore: 8080 };
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const FIRESTORE_BASE =
  `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// The adapter's own base URL, set by the test runner.
const ADAPTER = process.env.GUYUB_ADAPTER_URL ?? 'http://127.0.0.1:8080';

async function request(method, url, { token, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, {
    method,
    headers,
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) {}
  return { status: response.status, body: payload };
}

async function createAccount() {
  const number = crypto.randomUUID();
  const result = await request(
    'POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, {
      body: {
        returnSecureToken: true,
        email: `seam-${number}@example.invalid`,
        password: 'test-password-123',
      },
    },
  );
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}

function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}

// Firestore rules deny all client writes, so seeding needs the emulator's
// owner bypass — the same literal `owner` token the existing emulator tests use.
async function seedDocument(collection, id, record) {
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner',
    body: { fields: firestoreFields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

function encodeFirestoreValue(value) {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  throw new Error(`Unsupported test Firestore value: ${String(value)}`);
}

function firestoreFields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [
    key, encodeFirestoreValue(value),
  ]));
}

async function seedOperator(uid) {
  await seedDocument('operators', uid, {
    active: true,
    role: 'KETUA_RT_RW',
    rtId: 'rt-seam-test',
  });
}

test('adapter reports every callable and task it exposes', async () => {
  const health = await request('GET', `${ADAPTER}/health`);
  assert.equal(health.status, 200);
  assert.equal(health.body.callables, callableNames.length);
  assert.equal(health.body.ok, true);
});

test('unknown callable is a not-found, never a crash', async () => {
  const result = await request('POST', `${ADAPTER}/call/notARealCallable`, {
    body: { data: {} },
  });
  assert.equal(result.status, 404);
  assert.equal(result.body.error.code, 'not-found');
});

test('operator-only callable rejects an unauthenticated caller', async () => {
  // createTaskDraft is mode=operator; with no token, operatorUid is undefined
  // and the service must refuse rather than fall through.
  const result = await request('POST', `${ADAPTER}/call/createTaskDraft`, {
    body: { data: { templateId: 'safe-prep', locationCategory: 'HOUSEHOLD' } },
  });
  assert.ok(result.status === 401 || result.status === 403,
    `expected 401/403, got ${result.status}: ${JSON.stringify(result.body)}`);
  assert.ok(['permission-denied', 'unauthenticated', 'invalid-argument']
    .includes(result.body.error.code), JSON.stringify(result.body));
});

test('a verified operator token reaches the service layer', async () => {
  const account = await createAccount();
  await seedOperator(account.localId);

  // No rtId: the server derives the RT from operator membership and rejects a
  // client-supplied one (S-02). Sending it is itself a failure.
  const result = await request('POST', `${ADAPTER}/call/listActiveTaskCampaigns`, {
    token: account.idToken,
    body: { data: {} },
  });

  // No campaigns are seeded, so an empty list is the correct answer. What
  // matters is that the token was accepted and the callable ran.
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.ok(result.body.data !== undefined, JSON.stringify(result.body));
});

test('a client-supplied rtId is refused, not honoured', async () => {
  const account = await createAccount();
  await seedOperator(account.localId);

  // The new transport must not weaken the old boundary: a forged RT scope is
  // still rejected by the service, not accepted by the adapter.
  const result = await request('POST', `${ADAPTER}/call/listActiveTaskCampaigns`, {
    token: account.idToken,
    body: { data: { rtId: 'rt-somebody-else' } },
  });

  assert.equal(result.status, 400, JSON.stringify(result.body));
  assert.equal(result.body.error.code, 'invalid-argument');
});

test('a resident callable runs without any Firebase Auth token', async () => {
  // getEmergencyDirectory is mode=resident: the session token travels in data,
  // so no Authorization header is sent at all.
  const result = await request('POST', `${ADAPTER}/call/getEmergencyDirectory`, {
    body: { data: { sessionToken: 'not-a-real-session' } },
  });
  // The session is bogus, so the service must refuse — but it must reach the
  // service to decide that, not fail on transport.
  assert.ok([400, 403, 404].includes(result.status),
    `expected a domain refusal, got ${result.status}: ${JSON.stringify(result.body)}`);
  assert.ok(['permission-denied', 'invalid-argument', 'not-found', 'unauthenticated']
    .includes(result.body.error.code), JSON.stringify(result.body));
});

test('scheduled tasks require the shared secret', async () => {
  const result = await request('POST', `${ADAPTER}/tasks/deleteExpiredTaskEvidence`);
  assert.equal(result.status, 403);
  assert.equal(result.body.error.code, 'permission-denied');
});

test('a malformed body is rejected as invalid-argument', async () => {
  const response = await fetch(`${ADAPTER}/call/createResidentSession`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: '{not json',
  });
  assert.equal(response.status, 400);
  const payload = await response.json();
  assert.equal(payload.error.code, 'invalid-argument');
});
