const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');
const { proxyResidentDocumentId } = require('../src/proxy_resident_service');
const { responseDocumentId } = require('../src/task_response_service');

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
    method, headers, ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) {}
  return { status: response.status, body: payload };
}
async function createAccount({ anonymous = false } = {}) {
  const unique = crypto.randomUUID();
  const body = { returnSecureToken: true };
  if (!anonymous) {
    body.email = `proxy-resident-${unique}@example.invalid`;
    body.password = 'test-password-123';
  }
  const result = await request('POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, { body });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}
function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}
function firestoreValue(value) {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return { mapValue: { fields: fields(value) } };
  }
  throw new TypeError('Unsupported emulator fixture value.');
}
function fields(record) {
  return Object.fromEntries(Object.entries(record).map(([key, value]) => [key, firestoreValue(value)]));
}
async function seedDocument(collection, id, record) {
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner', body: { fields: fields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}
async function readDocument(collection, id) {
  return request('GET', documentUrl(collection, id), { token: 'owner' });
}
async function callFunction(name, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(`http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`, {
    method: 'POST', headers, body: JSON.stringify({ data }),
  });
  return { status: response.status, body: await response.json() };
}
function requestId() { return crypto.randomBytes(32).toString('base64url'); }
function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}
async function seedOperator(uid, rtId, role = 'KETUA_RT_RW', active = true) {
  await seedDocument('operators', uid, { rtId, role, active });
}

 test('proxy resident create/list/status is consent-attested, idempotent and RT-scoped', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-proxy-a-${suffix}`;
  const rtB = `rt-proxy-b-${suffix}`;
  const joinCode = `PX${suffix.slice(0, 14).toUpperCase()}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  const foreignOperator = await createAccount();
  const inactiveOperator = await createAccount();
  const invalidRoleOperator = await createAccount();
  const anonymous = await createAccount({ anonymous: true });
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtA, 'PENDAMPING_RT');
  await seedOperator(foreignOperator.localId, rtB);
  await seedOperator(inactiveOperator.localId, rtA, 'KETUA_RT_RW', false);
  await seedOperator(invalidRoleOperator.localId, rtA, 'RESIDENT');
  await seedDocument('rt_communities', rtA, {
    displayName: 'RT A', rtLabel: 'RT A', joinCodeHash: hashJoinCode(joinCode), joinCodeActive: true,
  });
  const appResidentId = 'c'.repeat(40);
  await seedDocument('resident_profiles', appResidentId, {
    residentId: appResidentId, rtId: rtA, nickname: 'Warga aplikasi',
    needsAssistance: false, createdBy: 'self',
  });
  const createPayload = {
    nickname: 'Nenek Sari', houseNumber: '12A', needsAssistance: true,
    residentConsentConfirmed: true, requestId: requestId(),
  };
  const created = await callFunction('createProxyResident', createPayload, operatorA.idToken);
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const profile = created.body.result;
  const expectedResidentId = proxyResidentDocumentId(rtA, createPayload.requestId);
  assert.equal(profile.residentId, expectedResidentId);
  assert.equal(profile.nickname, 'Nenek Sari');
  assert.equal(profile.houseNumber, '12A');
  assert.equal(profile.needsAssistance, true);
  assert.equal('rtId' in profile, false);
  assert.equal('createdBy' in profile, false);
  const createAudit = await readDocument('proxy_status_audit_events', `${expectedResidentId}_created`);
  assert.equal(createAudit.status, 200, JSON.stringify(createAudit.body));
  assert.equal(createAudit.body.fields.action.stringValue, 'PROXY_RESIDENT_CREATED');
  assert.equal(createAudit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(createAudit.body.fields.residentConsentConfirmed.booleanValue, true);
  assert.equal(createAudit.body.fields.needsAssistance.booleanValue, true);
  assert.equal(createAudit.body.fields.nickname, undefined);

  const replay = await callFunction('createProxyResident', createPayload, operatorA.idToken);
  assert.deepEqual(replay.body.result, profile);
  assertError(await callFunction('createProxyResident', {
    ...createPayload, nickname: 'Nama berbeda',
  }, operatorA.idToken), 'ALREADY_EXISTS');
  assertError(await callFunction('createProxyResident', {
    ...createPayload, requestId: requestId(), residentConsentConfirmed: false,
  }, operatorA.idToken), 'FAILED_PRECONDITION');
  assertError(await callFunction('createProxyResident', createPayload), 'PERMISSION_DENIED');
  assertError(await callFunction('createProxyResident', createPayload, anonymous.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('createProxyResident', createPayload, inactiveOperator.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('createProxyResident', createPayload, invalidRoleOperator.idToken), 'PERMISSION_DENIED');

  const listA = await callFunction('listProxyResidents', {}, operatorA.idToken);
  assert.equal(listA.status, 200, JSON.stringify(listA.body));
  assert.deepEqual(listA.body.result.items.map((item) => item.residentId), [expectedResidentId]);
  const listB = await callFunction('listProxyResidents', {}, foreignOperator.idToken);
  assert.equal(listB.status, 200, JSON.stringify(listB.body));
  assert.equal(listB.body.result.items.length, 0);
  assertError(await callFunction('listProxyResidents', { rtId: rtB }, operatorA.idToken), 'INVALID_ARGUMENT');

  const assistancePayload = {
    residentId: expectedResidentId, needsAssistance: false,
    residentConsentConfirmed: true, commandId: requestId(),
  };
  const assistance = await callFunction(
    'updateProxyResidentAssistance', assistancePayload, operatorB.idToken,
  );
  assert.equal(assistance.status, 200, JSON.stringify(assistance.body));
  assert.equal(assistance.body.result.needsAssistance, false);
  const assistanceReplay = await callFunction(
    'updateProxyResidentAssistance', assistancePayload, operatorB.idToken,
  );
  assert.deepEqual(assistanceReplay.body.result, assistance.body.result);
  assertError(await callFunction('updateProxyResidentAssistance', {
    ...assistancePayload, needsAssistance: true,
  }, operatorB.idToken), 'ALREADY_EXISTS');
  const assistanceHash = crypto.createHash('sha256')
    .update(assistancePayload.commandId).digest('hex');
  const assistanceAudit = await readDocument(
    'proxy_status_audit_events', `${expectedResidentId}_assistance_${assistanceHash}`,
  );
  assert.equal(assistanceAudit.status, 200, JSON.stringify(assistanceAudit.body));
  assert.equal(assistanceAudit.body.fields.action.stringValue, 'PROXY_ASSISTANCE_STATUS_UPDATED');
  assert.equal(assistanceAudit.body.fields.actorUid.stringValue, operatorB.localId);
  assert.equal(assistanceAudit.body.fields.residentConsentConfirmed.booleanValue, true);
  assert.equal(assistanceAudit.body.fields.nickname, undefined);
  assertError(await callFunction('updateProxyResidentAssistance', {
    residentId: expectedResidentId, needsAssistance: true,
    residentConsentConfirmed: false, commandId: requestId(),
  }, operatorA.idToken), 'FAILED_PRECONDITION');
  assertError(await callFunction('updateProxyResidentAssistance', {
    residentId: expectedResidentId, needsAssistance: true,
    residentConsentConfirmed: true, commandId: requestId(),
  }, foreignOperator.idToken), 'PERMISSION_DENIED');
  const assistanceAfterCrossRtAttempt = await readDocument('resident_profiles', expectedResidentId);
  assert.equal(assistanceAfterCrossRtAttempt.body.fields.needsAssistance.booleanValue, false);

  const taskA = crypto.createHash('sha256').update(`task-a-${suffix}`).digest('hex').slice(0, 40);
  const taskB = crypto.createHash('sha256').update(`task-b-${suffix}`).digest('hex').slice(0, 40);
  const deadline = new Date(Date.now() + 86_400_000);
  const campaign = (campaignId, rtId) => ({
    campaignId, rtId, status: 'ACTIVE', deadline,
    templateSnapshot: {
      templateId: 'safe_household_prep', version: 1,
      title: 'Persiapan rumah tangga', category: 'HOUSEHOLD_PREPARATION',
      coreInstruction: 'Simpan dokumen penting dalam wadah kedap air.',
      safetyInstruction: 'Jangan mendekati aliran berbahaya.',
    },
  });
  await seedDocument('task_campaigns', taskA, campaign(taskA, rtA));
  await seedDocument('task_campaigns', taskB, campaign(taskB, rtB));
  const statusPayload = {
    residentId: expectedResidentId, taskId: taskA, participationState: 'JOINED',
    completionReported: false, residentConsentConfirmed: true, commandId: requestId(),
  };
  const status = await callFunction('updateProxyTaskStatus', statusPayload, operatorA.idToken);
  assert.equal(status.status, 200, JSON.stringify(status.body));
  assert.equal(status.body.result.participationState, 'JOINED');
  assert.equal(status.body.result.completionState, 'NOT_SUBMITTED');
  const responseId = responseDocumentId(rtA, taskA, expectedResidentId);
  const responseBefore = await readDocument('task_responses', responseId);
  assert.equal(responseBefore.status, 200, JSON.stringify(responseBefore.body));
  assert.equal(responseBefore.body.fields.proxyRecordedBy.booleanValue, true);
  const statusReplay = await callFunction('updateProxyTaskStatus', statusPayload, operatorA.idToken);
  assert.deepEqual(statusReplay.body.result, status.body.result);
  const currentStatus = await callFunction('getProxyTaskStatus', {
    residentId: expectedResidentId, taskId: taskA,
  }, operatorB.idToken);
  assert.deepEqual(currentStatus.body.result, {
    taskId: taskA,
    participationState: 'JOINED',
    completionState: 'NOT_SUBMITTED',
  });
  assertError(await callFunction('getProxyTaskStatus', {
    residentId: expectedResidentId, taskId: taskB,
  }, operatorA.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('updateProxyTaskStatus', {
    ...statusPayload, completionReported: true,
  }, operatorA.idToken), 'ALREADY_EXISTS');
  const rawCommandHash = crypto.createHash('sha256').update(statusPayload.commandId).digest('hex');
  const statusAudit = await readDocument('proxy_status_audit_events', `${responseId}_${rawCommandHash}`);
  assert.equal(statusAudit.status, 200, JSON.stringify(statusAudit.body));
  assert.equal(statusAudit.body.fields.action.stringValue, 'PROXY_PARTICIPATION_RECORDED');
  assert.equal('nickname' in statusAudit.body.fields, false);
  assert.equal('houseNumber' in statusAudit.body.fields, false);
  assert.equal(statusAudit.body.fields.commandHash.stringValue, rawCommandHash);

  const completionPayload = {
    ...statusPayload, completionReported: true, commandId: requestId(),
  };
  const completed = await callFunction(
    'updateProxyTaskStatus', completionPayload, operatorB.idToken,
  );
  assert.equal(completed.status, 200, JSON.stringify(completed.body));
  assert.equal(completed.body.result.completionState, 'PENDING_RT_VERIFICATION');
  const completionReplay = await callFunction(
    'updateProxyTaskStatus', completionPayload, operatorB.idToken,
  );
  assert.deepEqual(completionReplay.body.result, completed.body.result);
  const completionHash = crypto.createHash('sha256')
    .update(completionPayload.commandId).digest('hex');
  const completionAudit = await readDocument(
    'proxy_status_audit_events', `${responseId}_${completionHash}`,
  );
  assert.equal(completionAudit.status, 200, JSON.stringify(completionAudit.body));
  assert.equal(completionAudit.body.fields.action.stringValue, 'PROXY_COMPLETION_REPORTED');
  assert.equal(completionAudit.body.fields.residentConsentConfirmed.booleanValue, true);
  const pendingResponse = await readDocument('task_responses', responseId);
  assert.equal(pendingResponse.body.fields.completionState.stringValue, 'PENDING_RT_VERIFICATION');
  assert.deepEqual(pendingResponse.body.fields.verifiedAt, { nullValue: null });
  assert.deepEqual(pendingResponse.body.fields.verifiedByOperatorUid, { nullValue: null });
  assert.deepEqual(pendingResponse.body.fields.completionNote, { nullValue: null });
  assertError(await callFunction('updateProxyTaskStatus', {
    ...statusPayload, residentId: appResidentId, commandId: requestId(),
  }, operatorA.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('updateProxyTaskStatus', {
    ...statusPayload, taskId: taskB, commandId: requestId(),
  }, operatorA.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('updateProxyTaskStatus', {
    ...statusPayload, commandId: requestId(), residentId: expectedResidentId,
  }, foreignOperator.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('updateProxyTaskStatus', {
    ...statusPayload, commandId: requestId(), residentId: expectedResidentId,
  }), 'PERMISSION_DENIED');
  assertError(await callFunction('verifyTaskCompletion', {
    responseId, commandId: requestId(),
  }, foreignOperator.idToken), 'PERMISSION_DENIED');
  const verified = await callFunction('verifyTaskCompletion', {
    responseId, commandId: requestId(),
  }, operatorA.idToken);
  assert.equal(verified.status, 200, JSON.stringify(verified.body));
  assert.equal(verified.body.result.completionState, 'VERIFIED_COMPLETE');

  const directRead = await request('GET', documentUrl('resident_profiles', expectedResidentId), {
    token: operatorA.idToken,
  });
  assert.notEqual(directRead.status, 200);
  const directWrite = await request('PATCH', documentUrl('resident_profiles', expectedResidentId), {
    token: operatorA.idToken, body: { fields: { needsAssistance: { booleanValue: false } } },
  });
  assert.notEqual(directWrite.status, 200);

  const storedProfile = await readDocument('resident_profiles', expectedResidentId);
  assert.equal(storedProfile.status, 200, JSON.stringify(storedProfile.body));
  assert.equal(storedProfile.body.fields.createdBy.stringValue, 'proxy');
  assert.equal(storedProfile.body.fields.needsAssistance.booleanValue, false);
  assert.equal(storedProfile.body.fields.nik, undefined);
  assert.equal(storedProfile.body.fields.address, undefined);
  assert.equal(storedProfile.body.fields.gps, undefined);
  assert.equal(storedProfile.body.fields.proxyRequestHash, undefined);
  assert.equal(storedProfile.body.fields.proxyProfileFingerprint, undefined);
  assert.equal(storedProfile.body.fields.proxyCreatedByOperatorUid, undefined);
});
