const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, functions: 5001, firestore: 8080 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;

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
        email: `emergency-directory-${number}@example.invalid`,
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

function encodeFirestoreValue(value) {
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encodeFirestoreValue) } };
  }
  if (value && typeof value === 'object') {
    return { mapValue: { fields: firestoreFields(value) } };
  }
  throw new Error(`Unsupported test Firestore value: ${String(value)}`);
}

function firestoreFields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [
    key, encodeFirestoreValue(value),
  ]));
}

async function seedDocument(collection, id, record) {
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner',
    body: { fields: firestoreFields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

async function seedCommunity(rtId, joinCode) {
  await seedDocument('rt_communities', rtId, {
    displayName: `Komunitas ${rtId}`,
    rtLabel: 'RT Uji',
    joinCodeHash: hashJoinCode(joinCode),
    joinCodeActive: true,
  });
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

function randomRequestId() {
  return crypto.randomBytes(32).toString('base64url');
}

function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}

async function createResident(joinCode, nickname) {
  const response = await callFunction('createResidentSession', {
    joinCode,
    nickname,
    requestId: randomRequestId(),
  });
  assert.equal(response.status, 200, JSON.stringify(response.body));
  return response.body.result;
}

function directoryRecord(rtId, overrides = {}) {
  return {
    rtId,
    state: 'ACTIVE',
    version: 1,
    lastVerifiedAt: new Date(),
    emergencyContacts: [{ label: 'Kontak uji', phone: '+62 21 555 0101' }],
    assemblyPoints: [{ label: 'Titik kumpul uji', publicLocation: 'Balai warga uji' }],
    officialReportChannels: [{ label: 'Laporan resmi uji', url: 'https://example.gov.id/report' }],
    ...overrides,
  };
}

test('resident callable reads only its RT directory, denies forged identity and direct client access', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-emergency-a-${suffix}`;
  const rtB = `rt-emergency-b-${suffix}`;
  const rtUnconfigured = `rt-emergency-c-${suffix}`;
  const codeA = `EA${suffix.slice(0, 14).toUpperCase()}`;
  const codeB = `EB${suffix.slice(0, 14).toUpperCase()}`;
  const codeC = `EC${suffix.slice(0, 14).toUpperCase()}`;
  await Promise.all([
    seedCommunity(rtA, codeA),
    seedCommunity(rtB, codeB),
    seedCommunity(rtUnconfigured, codeC),
  ]);
  await seedDocument('emergency_directories', rtA, directoryRecord(rtA));
  await seedDocument('emergency_directories', rtB, directoryRecord(rtB, {
    emergencyContacts: [{ label: 'Kontak RT B uji', phone: '110' }],
    assemblyPoints: [{ label: 'Titik RT B uji', publicLocation: 'Pos ronda uji' }],
  }));

  const [residentA, residentSameRt, residentB, residentUnconfigured] = await Promise.all([
    createResident(codeA, 'Warga A uji'),
    createResident(codeA, 'Warga A2 uji'),
    createResident(codeB, 'Warga B uji'),
    createResident(codeC, 'Warga C uji'),
  ]);
  const [first, sameRt, otherRt, unconfigured] = await Promise.all([
    callFunction('getEmergencyDirectory', { sessionToken: residentA.sessionToken }),
    callFunction('getEmergencyDirectory', { sessionToken: residentSameRt.sessionToken }),
    callFunction('getEmergencyDirectory', { sessionToken: residentB.sessionToken }),
    callFunction('getEmergencyDirectory', { sessionToken: residentUnconfigured.sessionToken }),
  ]);
  for (const response of [first, sameRt, otherRt]) {
    assert.equal(response.status, 200, JSON.stringify(response.body));
  }
  assert.deepEqual(first.body.result, sameRt.body.result);
  assert.equal(first.body.result.state, 'ACTIVE');
  assert.deepEqual(first.body.result.emergencyContacts, [
    { label: 'Kontak uji', phone: '+62 21 555 0101' },
  ]);
  assert.equal(otherRt.body.result.emergencyContacts[0].phone, '110');
  assert.deepEqual(unconfigured.body.result, { state: 'UNCONFIGURED' });
  for (const result of [first.body.result, otherRt.body.result]) {
    assert.equal('rtId' in result, false);
    assert.equal('residentId' in result, false);
  }

  for (const forged of [
    { sessionToken: residentA.sessionToken, rtId: rtB },
    { sessionToken: residentA.sessionToken, residentId: residentSameRt.residentId },
    { sessionToken: residentA.sessionToken, operatorUid: 'forged-operator' },
  ]) {
    assertError(await callFunction('getEmergencyDirectory', forged), 'INVALID_ARGUMENT');
  }

  const client = await createAccount();
  const directRead = await request('GET', documentUrl('emergency_directories', rtA), {
    token: client.idToken,
  });
  assert.notEqual(directRead.status, 200, JSON.stringify(directRead.body));
  assert.ok([401, 403].includes(directRead.status), JSON.stringify(directRead.body));
  const directWrite = await request('PATCH', documentUrl('emergency_directories', rtA), {
    token: client.idToken,
    body: { fields: firestoreFields(directoryRecord(rtA)) },
  });
  assert.notEqual(directWrite.status, 200, JSON.stringify(directWrite.body));
  assert.ok([401, 403].includes(directWrite.status), JSON.stringify(directWrite.body));

  await seedDocument('emergency_directories', rtB, directoryRecord(rtB, { version: 0 }));
  assertError(await callFunction('getEmergencyDirectory', {
    sessionToken: residentB.sessionToken,
  }), 'FAILED_PRECONDITION');
});
