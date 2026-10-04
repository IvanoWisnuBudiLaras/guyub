const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { functions: 5001, firestore: 8080 };
const COMMUNITY_A = 'rt-session-test-a';
const COMMUNITY_B = 'rt-session-test-b';
const CODE_A = 'A2345678BCDE';
const CODE_B = 'F2345678GHIJ';

async function firestoreRequest(method, path, body, { owner = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (owner) headers.Authorization = 'Bearer owner';
  const response = await fetch(
    `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`,
    { method, headers, ...(body ? { body: JSON.stringify(body) } : {}) },
  );
  const text = await response.text();
  let data = {};
  try { data = text ? JSON.parse(text) : {}; } catch (_) {}
  return { status: response.status, body: data };
}

async function seedCommunity(id, code) {
  const response = await firestoreRequest('PATCH', `rt_communities/${id}`, {
    fields: {
      displayName: { stringValue: `Demo ${id}` },
      rtLabel: { stringValue: 'RT Uji' },
      joinCodeHash: { stringValue: hashJoinCode(code) },
      joinCodeActive: { booleanValue: true },
    },
  }, { owner: true });
  assert.equal(response.status, 200, JSON.stringify(response.body));
}

async function callFunction(name, data) {
  const response = await fetch(
    `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data }),
    },
  );
  return { status: response.status, body: await response.json() };
}

test('callable creates, validates, and revokes an opaque RT-scoped resident session', async () => {
  await seedCommunity(COMMUNITY_A, CODE_A);
  await seedCommunity(COMMUNITY_B, CODE_B);

  const enrollmentRequestId = crypto.randomBytes(32).toString('base64url');
  const createdResponse = await callFunction('createResidentSession', {
    joinCode: CODE_A,
    nickname: 'Sari',
    requestId: enrollmentRequestId,
  });
  assert.equal(createdResponse.status, 200, JSON.stringify(createdResponse.body));
  const firstCreated = createdResponse.body.result;
  assert.equal(firstCreated.communityId, COMMUNITY_A);
  assert.equal(firstCreated.rtLabel, 'RT Uji');
  assert.equal(firstCreated.nickname, 'Sari');
  assert.match(firstCreated.sessionToken, /^[A-Za-z0-9_-]{32,128}$/);

  const firstTokenHash = crypto.createHash('sha256')
    .update(firstCreated.sessionToken)
    .digest('hex');
  const sessionResponse = await firestoreRequest(
    'GET', `resident_sessions/${firstTokenHash}`, undefined, { owner: true },
  );
  assert.equal(sessionResponse.status, 200, JSON.stringify(sessionResponse.body));
  const sessionFields = sessionResponse.body.fields;
  assert.equal(sessionFields.rtId.stringValue, COMMUNITY_A);
  assert.equal(sessionFields.active.booleanValue, true);
  assert.equal(JSON.stringify(sessionFields).includes(firstCreated.sessionToken), false);

  const retryResponse = await callFunction('createResidentSession', {
    joinCode: CODE_A,
    nickname: 'Sari',
    requestId: enrollmentRequestId,
  });
  assert.equal(retryResponse.status, 200, JSON.stringify(retryResponse.body));
  const created = retryResponse.body.result;
  assert.equal(created.residentId, firstCreated.residentId);
  assert.notEqual(created.sessionToken, firstCreated.sessionToken);
  const retryTokenHash = crypto.createHash('sha256')
    .update(created.sessionToken)
    .digest('hex');
  const revokedRetry = await firestoreRequest(
    'GET', `resident_sessions/${firstTokenHash}`, undefined, { owner: true },
  );
  assert.equal(revokedRetry.body.fields.active.booleanValue, false);
  const activeRetry = await firestoreRequest(
    'GET', `resident_sessions/${retryTokenHash}`, undefined, { owner: true },
  );
  assert.equal(activeRetry.body.fields.active.booleanValue, true);

  const enrollmentHash = crypto.createHash('sha256')
    .update(enrollmentRequestId)
    .digest('hex');
  const enrollmentResponse = await firestoreRequest(
    'GET', `resident_enrollments/${enrollmentHash}`, undefined, { owner: true },
  );
  assert.equal(enrollmentResponse.status, 200, JSON.stringify(enrollmentResponse.body));
  assert.equal(enrollmentResponse.body.fields.sessionHash.stringValue, retryTokenHash);
  assert.match(enrollmentResponse.body.fields.requestFingerprint.stringValue, /^[a-f0-9]{64}$/);
  assert.equal(JSON.stringify(enrollmentResponse.body.fields).includes(enrollmentRequestId), false);
  assert.equal(JSON.stringify(enrollmentResponse.body.fields).includes('Sari'), false);

  const residentResponse = await firestoreRequest(
    'GET', `resident_profiles/${created.residentId}`, undefined, { owner: true },
  );
  assert.equal(residentResponse.status, 200, JSON.stringify(residentResponse.body));
  const residentFields = residentResponse.body.fields;
  assert.deepEqual(Object.keys(residentFields).sort(), [
    'createdAt', 'createdBy', 'needsAssistance', 'nickname', 'rtId', 'updatedAt',
  ]);
  for (const forbidden of ['nik', 'fullAddress', 'address', 'latitude', 'longitude', 'gps']) {
    assert.equal(Object.hasOwn(residentFields, forbidden), false);
  }

  const validated = await callFunction('validateResidentSession', {
    sessionToken: created.sessionToken,
    communityId: COMMUNITY_B,
  });
  assert.equal(validated.status, 200, JSON.stringify(validated.body));
  assert.equal(validated.body.result.communityId, COMMUNITY_A);

  const directRead = await firestoreRequest(
    'GET', `resident_profiles/${created.residentId}`,
  );
  assert.equal(directRead.status, 403);
  const directWrite = await firestoreRequest(
    'PATCH', 'resident_profiles/attacker', {
      fields: { nickname: { stringValue: 'intruder' } },
    },
  );
  assert.equal(directWrite.status, 403);
  const directEnrollmentRead = await firestoreRequest(
    'GET', `resident_enrollments/${enrollmentHash}`,
  );
  assert.equal(directEnrollmentRead.status, 403);
  const directEnrollmentWrite = await firestoreRequest(
    'PATCH', 'resident_enrollments/attacker', {
      fields: { requestFingerprint: { stringValue: 'fake' } },
    },
  );
  assert.equal(directEnrollmentWrite.status, 403);

  const revoked = await callFunction('revokeResidentSession', {
    sessionToken: created.sessionToken,
  });
  assert.equal(revoked.status, 200, JSON.stringify(revoked.body));
  const restored = await callFunction('validateResidentSession', {
    sessionToken: created.sessionToken,
  });
  assert.equal(restored.body.error.status, 'PERMISSION_DENIED');
});

test('invalid RT codes have one generic response and disclose no community', async () => {
  const first = await callFunction('createResidentSession', {
    joinCode: 'Z2345678ZZZZ',
    nickname: 'Warga',
    requestId: crypto.randomBytes(32).toString('base64url'),
  });
  const malformed = await callFunction('createResidentSession', {
    joinCode: 'SHORT',
    nickname: 'Warga',
    requestId: crypto.randomBytes(32).toString('base64url'),
  });
  for (const response of [first, malformed]) {
    assert.notEqual(response.status, 200);
    assert.equal(response.body.error.status, 'PERMISSION_DENIED');
    assert.equal(response.body.error.message, 'Kode RT tidak valid atau tidak aktif.');
    assert.equal(JSON.stringify(response.body).includes(COMMUNITY_A), false);
    assert.equal(JSON.stringify(response.body).includes(COMMUNITY_B), false);
  }
});
