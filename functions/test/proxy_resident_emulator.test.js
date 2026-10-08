const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const { hashEnrollmentRequestId, hashJoinCode, hashSessionToken } =
  require('../src/resident_session_service');
const { buildStoragePath, residentScopeHash } = require('../src/task_evidence_service');
const { assignmentIdentity, assignmentPairIdentity } =
  require('../src/firestore_assistance_assignment_repository');
const { proxyResidentDocumentId } = require('../src/proxy_resident_service');
const { responseDocumentId } = require('../src/task_response_service');
const { residentProfileTombstoneId } = require('../src/resident_profile_tombstone');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const BUCKET_NAME = `${PROJECT_ID}.appspot.com`;
const PORTS = { auth: 9099, functions: 5001, firestore: 8080, storage: 9199 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const adminApp = getApps().find((app) => app.name === '[DEFAULT]') ??
  initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET_NAME });
const adminBucket = getStorage(adminApp).bucket(BUCKET_NAME);

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
  const appResidentId = '550e8400-e29b-41d4-a716-446655440000';
  await seedDocument('resident_profiles', appResidentId, {
    rtId: rtA, nickname: 'Warga aplikasi',
    needsAssistance: false, createdBy: 'self', createdAt: new Date('2026-01-01T00:00:00Z'),
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
  assert.deepEqual(listA.body.result.items.map((item) => item.residentId), [
    appResidentId, expectedResidentId,
  ]);
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
  const appResponseId = responseDocumentId(rtA, taskA, appResidentId);
  await seedDocument('task_responses', appResponseId, {
    responseId: appResponseId, taskId: taskA, rtId: rtA, residentId: appResidentId,
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });
  const appStatus = await callFunction('getProxyTaskStatus', {
    residentId: appResidentId, taskId: taskA,
  }, operatorA.idToken);
  assert.deepEqual(appStatus.body.result, {
    taskId: taskA, participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });
  assertError(await callFunction('updateProxyTaskStatus', {
    residentId: appResidentId, taskId: taskA, participationState: 'DECLINED',
    completionReported: false, residentConsentConfirmed: true, commandId: requestId(),
  }, operatorA.idToken), 'FAILED_PRECONDITION');
  const appCompletion = await callFunction('updateProxyTaskStatus', {
    residentId: appResidentId, taskId: taskA, participationState: 'JOINED',
    completionReported: true, residentConsentConfirmed: true, commandId: requestId(),
  }, operatorA.idToken);
  assert.equal(appCompletion.status, 200, JSON.stringify(appCompletion.body));
  assert.equal(appCompletion.body.result.completionState, 'PENDING_RT_VERIFICATION');
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
  const selfResidentReplay = await callFunction('updateProxyTaskStatus', {
    ...statusPayload, residentId: appResidentId, commandId: requestId(),
  }, operatorA.idToken);
  assert.equal(selfResidentReplay.status, 200, JSON.stringify(selfResidentReplay.body));
  assert.equal(selfResidentReplay.body.result.completionState, 'PENDING_RT_VERIFICATION');
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

test('RT-assisted deletion verifies scope, revokes data, removes evidence, and replays safely', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-delete-a-${suffix}`;
  const rtB = `rt-delete-b-${suffix}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtB);
  const joinCode = `DL${suffix.slice(0, 14).toUpperCase()}`;
  await seedDocument('rt_communities', rtA, {
    displayName: 'RT Hapus', rtLabel: 'RT A',
    joinCodeHash: hashJoinCode(joinCode), joinCodeActive: true,
  });
  const enrollmentRequestId = requestId();
  const enrollment = await callFunction('createResidentSession', {
    joinCode, nickname: 'Warga Hapus', requestId: enrollmentRequestId,
  });
  assert.equal(enrollment.status, 200, JSON.stringify(enrollment.body));
  const residentId = enrollment.body.result.residentId;
  const sessionToken = enrollment.body.result.sessionToken;
  const sessionId = hashSessionToken(sessionToken);
  const taskId = crypto.createHash('sha256').update(`delete-task-${suffix}`).digest('hex').slice(0, 40);
  const responseId = responseDocumentId(rtA, taskId, residentId);
  const evidenceId = crypto.createHash('sha256').update(`evidence-${suffix}`).digest('hex').slice(0, 40);
  const enrollmentId = hashEnrollmentRequestId(enrollmentRequestId);
  assert.equal((await readDocument('resident_profiles', residentId)).body.fields.residentId, undefined);
  await seedDocument('task_responses', responseId, {
    responseId, taskId, rtId: rtA, residentId,
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });
  const evidencePath = buildStoragePath(rtA, taskId, residentId, evidenceId);
  await adminBucket.file(evidencePath).save(Buffer.from('temporary resident evidence'));
  assert.deepEqual(await adminBucket.file(evidencePath).exists(), [true]);
  await seedDocument('task_evidence', evidenceId, {
    evidenceId, rtId: rtA, taskId, responseId,
    residentScopeHash: residentScopeHash(rtA, residentId),
    storagePath: evidencePath,
    status: 'READY',
  });
  await seedDocument('resident_proposals', `proposal-${suffix}`, {
    proposalId: `proposal-${suffix}`, residentId, rtId: rtA,
    title: 'Private title', description: 'Private text',
  });
  await seedDocument('resident_push_tokens', `token-${suffix}`, {
    residentId, rtId: rtA, token: 'private-fcm-token',
  });
  await seedDocument('proxy_status_audit_events', `proxy-audit-${suffix}`, {
    targetResidentId: residentId, rtId: rtA, action: 'TEST_ONLY',
  });
  await seedDocument('assistance_assignments', `assignment-target-${suffix}`, {
    assignmentId: `assignment-target-${suffix}`, rtId: rtA,
    residentNeedingHelpId: residentId, helperResidentId: 'd'.repeat(40), state: 'OFFERED',
  });
  await seedDocument('assistance_assignments', `assignment-helper-${suffix}`, {
    assignmentId: `assignment-helper-${suffix}`, rtId: rtA,
    residentNeedingHelpId: 'e'.repeat(40), helperResidentId: residentId, state: 'ACCEPTED',
  });
  const pairGuardId = assignmentPairIdentity(rtA, residentId, 'd'.repeat(40));
  await seedDocument('assistance_assignment_pair_guards', pairGuardId, {
    pairId: pairGuardId, rtId: rtA, residentNeedingHelpId: residentId,
    helperResidentId: 'd'.repeat(40), activeAssignmentId: `assignment-target-${suffix}`,
  });
  const residentHash = crypto.createHash('sha256')
    .update(`resident-assistance\0${rtA}\0${residentId}`).digest('hex');
  await seedDocument('assistance_assignment_audit_events', `audit-target-${suffix}`, {
    auditId: `audit-target-${suffix}`, rtId: rtA, targetResidentHash: residentHash,
  });
  await seedDocument('assistance_assignment_audit_events', `audit-helper-${suffix}`, {
    auditId: `audit-helper-${suffix}`, rtId: rtA, actorResidentHash: residentHash,
  });

  const payload = {
    residentId, commandId: requestId(), residentRequestConfirmed: true,
    identityVerificationConfirmed: true,
  };
  assertError(await callFunction('deleteResidentData', payload, operatorB.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('deleteResidentData', {
    ...payload, residentRequestConfirmed: false,
  }, operatorA.idToken), 'FAILED_PRECONDITION');
  assertError(await callFunction('deleteResidentData', payload), 'PERMISSION_DENIED');

  const deleted = await callFunction('deleteResidentData', payload, operatorA.idToken);
  assert.equal(deleted.status, 200, JSON.stringify(deleted.body));
  assert.deepEqual(deleted.body.result, { residentId, deleted: true });
  const replay = await callFunction('deleteResidentData', payload, operatorA.idToken);
  assert.deepEqual(replay.body.result, deleted.body.result);
  assert.deepEqual(await adminBucket.file(evidencePath).exists(), [false]);
  for (const [collection, id] of [
    ['resident_profiles', residentId], ['resident_sessions', sessionId],
    ['task_responses', responseId],
    ['task_evidence', evidenceId], ['resident_proposals', `proposal-${suffix}`],
    ['resident_push_tokens', `token-${suffix}`],
    ['proxy_status_audit_events', `proxy-audit-${suffix}`],
    ['assistance_assignments', `assignment-target-${suffix}`],
    ['assistance_assignments', `assignment-helper-${suffix}`],
    ['assistance_assignment_pair_guards', pairGuardId],
    ['assistance_assignment_audit_events', `audit-target-${suffix}`],
    ['assistance_assignment_audit_events', `audit-helper-${suffix}`],
  ]) {
    assert.equal((await readDocument(collection, id)).status, 404, `${collection}/${id} remains`);
  }
  const enrollmentTombstone = await readDocument('resident_enrollments', enrollmentId);
  assert.equal(enrollmentTombstone.status, 200, JSON.stringify(enrollmentTombstone.body));
  assert.deepEqual(Object.keys(enrollmentTombstone.body.fields).sort(), [
    'deletedAt', 'rtId', 'status',
  ]);
  assert.equal(enrollmentTombstone.body.fields.status.stringValue, 'DELETED');
  assert.equal(enrollmentTombstone.body.fields.residentId, undefined);
  assert.equal(enrollmentTombstone.body.fields.sessionHash, undefined);
  assert.equal(enrollmentTombstone.body.fields.requestFingerprint, undefined);
  assertError(await callFunction('createResidentSession', {
    joinCode, nickname: 'Warga Hapus', requestId: enrollmentRequestId,
  }), 'PERMISSION_DENIED');
  const targetHash = crypto.createHash('sha256')
    .update(`resident-deletion\0${rtA}\0${residentId}`).digest('hex');
  const audit = await readDocument('resident_data_deletion_audit_events', targetHash);
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.action.stringValue, 'RESIDENT_DATA_DELETED');
  assert.equal(audit.body.fields.targetResidentHash.stringValue, targetHash);
  assert.equal(audit.body.fields.residentId, undefined);

  const pendingResidentId = crypto.createHash('sha256')
    .update(`delete-pending-${suffix}`).digest('hex').slice(0, 40);
  const pendingEvidenceId = crypto.createHash('sha256')
    .update(`pending-evidence-${suffix}`).digest('hex').slice(0, 40);
  await seedDocument('resident_profiles', pendingResidentId, {
    residentId: pendingResidentId, rtId: rtA, nickname: 'Warga Tertunda',
    needsAssistance: false, createdBy: 'proxy', createdAt: new Date(),
  });
  const pendingResponseId = responseDocumentId(rtA, taskId, pendingResidentId);
  const evidenceFixture = {
    evidenceId: pendingEvidenceId, rtId: rtA, taskId,
    responseId: pendingResponseId,
    residentScopeHash: residentScopeHash(rtA, pendingResidentId),
    status: 'READY',
  };
  await seedDocument('task_evidence', pendingEvidenceId, evidenceFixture);
  const uploadingEvidenceId = crypto.createHash('sha256')
    .update(`uploading-evidence-${suffix}`).digest('hex').slice(0, 40);
  const uploadingPath = buildStoragePath(rtA, taskId, pendingResidentId, uploadingEvidenceId);
  const uploadingFixture = {
    evidenceId: uploadingEvidenceId, rtId: rtA, taskId,
    responseId: pendingResponseId,
    residentScopeHash: residentScopeHash(rtA, pendingResidentId),
    storagePath: uploadingPath,
    status: 'UPLOADING',
    createdAt: new Date(),
    uploadLeaseUntil: new Date(Date.now() + 60_000),
  };
  await adminBucket.file(uploadingPath).save(Buffer.from('expired upload evidence'));
  await seedDocument('task_evidence', uploadingEvidenceId, uploadingFixture);
  const retryPayload = {
    residentId: pendingResidentId, commandId: requestId(),
    residentRequestConfirmed: true, identityVerificationConfirmed: true,
  };
  assertError(await callFunction('deleteResidentData', retryPayload, operatorA.idToken), 'FAILED_PRECONDITION');
  const pendingList = await callFunction('listProxyResidents', {}, operatorA.idToken);
  const pendingProfile = pendingList.body.result.items.find(
    (item) => item.residentId === pendingResidentId,
  );
  assert.equal(pendingProfile?.deletionPending, true);
  assertError(await callFunction('updateProxyResidentAssistance', {
    residentId: pendingResidentId, needsAssistance: true,
    residentConsentConfirmed: true, commandId: requestId(),
  }, operatorA.idToken), 'PERMISSION_DENIED');
  await seedDocument('task_evidence', pendingEvidenceId, {
    ...evidenceFixture,
    storagePath: buildStoragePath(rtA, taskId, pendingResidentId, pendingEvidenceId),
  });
  assertError(await callFunction('deleteResidentData', retryPayload, operatorA.idToken), 'FAILED_PRECONDITION');
  await seedDocument('task_evidence', uploadingEvidenceId, {
    ...uploadingFixture, status: 'DELETE_PENDING',
  });
  assertError(await callFunction('deleteResidentData', retryPayload, operatorA.idToken), 'FAILED_PRECONDITION');
  assert.deepEqual(await adminBucket.file(uploadingPath).exists(), [true]);
  await seedDocument('task_evidence', uploadingEvidenceId, {
    ...uploadingFixture,
    uploadLeaseUntil: new Date(Date.now() - 1000),
  });
  const retry = await callFunction('deleteResidentData', retryPayload, operatorA.idToken);
  assert.equal(retry.status, 200, JSON.stringify(retry.body));
  assert.equal((await adminBucket.file(uploadingPath).exists())[0], false);
  assert.equal((await readDocument('resident_profiles', pendingResidentId)).status, 404);
  assert.equal((await readDocument('task_evidence', pendingEvidenceId)).status, 404);
  assert.equal((await readDocument('task_evidence', uploadingEvidenceId)).status, 404);
});

test('pending proxy create cancellation is scoped and serialized with create', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-cancel-${suffix}`;
  const operator = await createAccount();
  await seedOperator(operator.localId, rtId);
  const requestIdValue = requestId();
  const createPayload = {
    nickname: 'Warga Dibatalkan', houseNumber: null, needsAssistance: false,
    residentConsentConfirmed: true, requestId: requestIdValue,
  };
  const [create, cancellation] = await Promise.all([
    callFunction('createProxyResident', createPayload, operator.idToken),
    callFunction('cancelPendingProxyResidentCreate', {
      requestId: requestIdValue,
    }, operator.idToken),
  ]);
  assert.equal(cancellation.status, 200, JSON.stringify(cancellation.body));
  const residentId = proxyResidentDocumentId(rtId, requestIdValue);
  const repeated = await callFunction('cancelPendingProxyResidentCreate', {
    requestId: requestIdValue,
  }, operator.idToken);
  assert.equal(repeated.status, 200, JSON.stringify(repeated.body));
  if (create.status === 200) {
    assert.deepEqual(cancellation.body.result, { state: 'CREATED' });
    assert.deepEqual(repeated.body.result, { state: 'CREATED' });
    assert.equal((await readDocument('resident_profiles', residentId)).status, 200);
    const createReplay = await callFunction('createProxyResident', createPayload, operator.idToken);
    assert.deepEqual(createReplay.body.result, create.body.result);
    assert.equal((await readDocument(
      'resident_profile_tombstones', residentProfileTombstoneId(rtId, residentId),
    )).status, 404);
  } else {
    assertError(create, 'FAILED_PRECONDITION');
    assert.deepEqual(cancellation.body.result, { state: 'CANCELLED' });
    assert.deepEqual(repeated.body.result, { state: 'CANCELLED' });
    assert.equal((await readDocument('resident_profiles', residentId)).status, 404);
    const tombstone = await readDocument(
      'resident_profile_tombstones', residentProfileTombstoneId(rtId, residentId),
    );
    assert.equal(tombstone.status, 200, JSON.stringify(tombstone.body));
    assert.equal(tombstone.body.fields.action.stringValue, 'PROXY_CREATE_CANCELLED');
  }
});

test('a proxy deletion tombstone prevents delayed create replay', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-tombstone-${suffix}`;
  const operator = await createAccount();
  await seedOperator(operator.localId, rtId);
  const requestIdValue = requestId();
  const createPayload = {
    nickname: 'Warga Selesai', houseNumber: null, needsAssistance: false,
    residentConsentConfirmed: true, requestId: requestIdValue,
  };
  const created = await callFunction('createProxyResident', createPayload, operator.idToken);
  assert.equal(created.status, 200, JSON.stringify(created.body));
  const residentId = created.body.result.residentId;
  const reconcile = await callFunction('cancelPendingProxyResidentCreate', {
    requestId: requestIdValue,
  }, operator.idToken);
  assert.deepEqual(reconcile.body.result, { state: 'CREATED' });
  const deletePayload = {
    residentId, commandId: requestId(),
    residentRequestConfirmed: true, identityVerificationConfirmed: true,
  };
  const deleted = await callFunction('deleteResidentData', deletePayload, operator.idToken);
  assert.equal(deleted.status, 200, JSON.stringify(deleted.body));
  assert.equal((await readDocument('resident_profiles', residentId)).status, 404);
  assertError(
    await callFunction('createProxyResident', createPayload, operator.idToken),
    'FAILED_PRECONDITION',
  );
  const repeatedDelete = await callFunction('deleteResidentData', deletePayload, operator.idToken);
  assert.deepEqual(repeatedDelete.body.result, deleted.body.result);
  const tombstoneId = residentProfileTombstoneId(rtId, residentId);
  const tombstone = await readDocument('resident_profile_tombstones', tombstoneId);
  assert.equal(tombstone.status, 200, JSON.stringify(tombstone.body));
  assert.equal(tombstone.body.fields.action.stringValue, 'RESIDENT_DATA_DELETED');
  assert.deepEqual(Object.keys(tombstone.body.fields).sort(), [
    'action', 'occurredAt', 'rtId', 'targetResidentHash', 'tombstoneId',
  ]);
  assert.equal(tombstone.body.fields.residentId, undefined);
});

test('helper assignment is opt-in, same-RT, private, voluntary and idempotent', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-helper-a-${suffix}`;
  const rtB = `rt-helper-b-${suffix}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtB);
  const joinCode = `HL${suffix.slice(0, 14).toUpperCase()}`;
  await seedDocument('rt_communities', rtA, {
    displayName: 'RT A', rtLabel: 'RT A',
    joinCodeHash: hashJoinCode(joinCode), joinCodeActive: true,
  });
  await seedDocument('rt_communities', rtB, { displayName: 'RT B', rtLabel: 'RT B' });

  const enrollment = await callFunction('createResidentSession', {
    joinCode, nickname: 'Relawan', requestId: requestId(),
  });
  assert.equal(enrollment.status, 200, JSON.stringify(enrollment.body));
  const helperId = enrollment.body.result.residentId;
  const helperToken = enrollment.body.result.sessionToken;
  const foreignHelperId = crypto.createHash('sha256').update(`foreign-helper-${suffix}`).digest('hex').slice(0, 40);
  const targetId = crypto.createHash('sha256').update(`target-${suffix}`).digest('hex').slice(0, 40);
  const target2Id = crypto.createHash('sha256').update(`target2-${suffix}`).digest('hex').slice(0, 40);
  const foreignToken = requestId();
  const foreignSessionId = hashSessionToken(foreignToken);
  const resident = (residentId, rtId, nickname, needsAssistance, createdBy, willingToHelp = false) => ({
    residentId, rtId, nickname, needsAssistance, createdBy, willingToHelp,
    createdAt: new Date(),
  });
  await seedDocument('resident_profiles', foreignHelperId,
    resident(foreignHelperId, rtB, 'Relawan lain', false, 'self', true));
  await seedDocument('resident_profiles', targetId,
    resident(targetId, rtA, 'Rumah A', true, 'proxy'));
  await seedDocument('resident_profiles', target2Id,
    resident(target2Id, rtA, 'Rumah B', true, 'proxy'));
  for (const [id, residentId, rtId] of [
    [foreignSessionId, foreignHelperId, rtB],
  ]) {
    await seedDocument('resident_sessions', id, {
      residentId, rtId, active: true, createdAt: new Date(),
      expiresAt: new Date(Date.now() + 86_400_000),
    });
  }

  const volunteerData = await callFunction(
    'getAssistanceVolunteerData', { sessionToken: helperToken },
  );
  assert.equal(volunteerData.status, 200, JSON.stringify(volunteerData.body));
  assert.equal(volunteerData.body.result.willingToHelp, false);
  assert.deepEqual(volunteerData.body.result.assignments, []);
  assertError(await callFunction('updateAssistanceVolunteerConsent', {
    sessionToken: helperToken, willingToHelp: true,
    residentConsentConfirmed: false, commandId: requestId(),
  }), 'FAILED_PRECONDITION');

  const optInPayload = {
    sessionToken: helperToken, willingToHelp: true,
    residentConsentConfirmed: true, commandId: requestId(),
  };
  const optIn = await callFunction('updateAssistanceVolunteerConsent', optInPayload);
  assert.equal(optIn.status, 200, JSON.stringify(optIn.body));
  assert.equal(optIn.body.result.willingToHelp, true);
  const optInReplay = await callFunction('updateAssistanceVolunteerConsent', optInPayload);
  assert.deepEqual(optInReplay.body.result, optIn.body.result);
  const helpers = await callFunction('listAvailableAssistanceHelpers', {}, operatorA.idToken);
  assert.deepEqual(helpers.body.result.items, [{ residentId: helperId, nickname: 'Relawan' }]);
  assert.deepEqual(
    (await callFunction('listAvailableAssistanceHelpers', {}, operatorB.idToken)).body.result.items,
    [{ residentId: foreignHelperId, nickname: 'Relawan lain' }],
  );

  const assignmentCommandId = requestId();
  const assignmentPayload = {
    residentId: targetId, helperResidentId: helperId, commandId: assignmentCommandId,
  };
  assertError(await callFunction('createAssistanceHelperAssignment', {
    ...assignmentPayload, helperResidentId: foreignHelperId,
  }, operatorA.idToken), 'PERMISSION_DENIED');
  const assigned = await callFunction(
    'createAssistanceHelperAssignment', assignmentPayload, operatorA.idToken,
  );
  assert.equal(assigned.status, 200, JSON.stringify(assigned.body));
  assert.equal(assigned.body.result.state, 'OFFERED');
  const commandHash = crypto.createHash('sha256').update(assignmentCommandId).digest('hex');
  const assignmentId = assignmentIdentity(rtA, targetId, helperId, commandHash);
  assert.equal(assigned.body.result.assignmentId, assignmentId);
  const replay = await callFunction(
    'createAssistanceHelperAssignment', assignmentPayload, operatorA.idToken,
  );
  assert.deepEqual(replay.body.result, assigned.body.result);
  assertError(await callFunction('createAssistanceHelperAssignment', {
    ...assignmentPayload, commandId: requestId(),
  }, operatorA.idToken), 'ALREADY_EXISTS');

  const offers = await callFunction('getAssistanceVolunteerData', { sessionToken: helperToken });
  assert.equal(offers.status, 200, JSON.stringify(offers.body));
  assert.deepEqual(offers.body.result.assignments.map((item) => item.assignmentId), [assignmentId]);
  assert.equal('residentNeedingHelpId' in offers.body.result.assignments[0], false);
  assert.equal('helperResidentId' in offers.body.result.assignments[0], false);
  const assignmentAudit = await readDocument(
    'assistance_assignment_audit_events', `${assignmentId}_created`,
  );
  assert.equal(assignmentAudit.status, 200, JSON.stringify(assignmentAudit.body));
  assert.equal(assignmentAudit.body.fields.targetResidentId, undefined);
  assert.equal(assignmentAudit.body.fields.helperResidentId, undefined);
  assert.equal(assignmentAudit.body.fields.nickname, undefined);

  const declinePayload = {
    sessionToken: helperToken, assignmentId, decision: 'DECLINED',
    residentConsentConfirmed: true, commandId: requestId(),
  };
  assertError(await callFunction('respondToAssistanceAssignment', {
    ...declinePayload, sessionToken: foreignToken,
  }), 'PERMISSION_DENIED');
  const declined = await callFunction('respondToAssistanceAssignment', declinePayload);
  assert.equal(declined.status, 200, JSON.stringify(declined.body));
  assert.equal(declined.body.result.state, 'DECLINED');
  assert.deepEqual((await callFunction(
    'getAssistanceVolunteerData', { sessionToken: helperToken },
  )).body.result.assignments, []);

  const optOut = await callFunction('updateAssistanceVolunteerConsent', {
    sessionToken: helperToken, willingToHelp: false,
    residentConsentConfirmed: true, commandId: requestId(),
  });
  assert.equal(optOut.body.result.willingToHelp, false);
  assertError(await callFunction('createAssistanceHelperAssignment', {
    residentId: target2Id, helperResidentId: helperId, commandId: requestId(),
  }, operatorA.idToken), 'PERMISSION_DENIED');

  await callFunction('updateAssistanceVolunteerConsent', {
    sessionToken: helperToken, willingToHelp: true,
    residentConsentConfirmed: true, commandId: requestId(),
  });
  const concurrentOffers = await Promise.all([
    callFunction('createAssistanceHelperAssignment', {
      residentId: targetId, helperResidentId: helperId, commandId: requestId(),
    }, operatorA.idToken),
    callFunction('createAssistanceHelperAssignment', {
      residentId: targetId, helperResidentId: helperId, commandId: requestId(),
    }, operatorA.idToken),
  ]);
  const successfulOffers = concurrentOffers.filter((response) => response.status === 200);
  const rejectedOffers = concurrentOffers.filter((response) => response.status !== 200);
  assert.equal(successfulOffers.length, 1, JSON.stringify(concurrentOffers));
  assert.equal(rejectedOffers.length, 1, JSON.stringify(concurrentOffers));
  assertError(rejectedOffers[0], 'ALREADY_EXISTS');
  const assigned2 = successfulOffers[0];
  const accepted = await callFunction('respondToAssistanceAssignment', {
    sessionToken: helperToken, assignmentId: assigned2.body.result.assignmentId,
    decision: 'ACCEPTED', residentConsentConfirmed: true, commandId: requestId(),
  });
  assert.equal(accepted.body.result.state, 'ACCEPTED');
  const withdrawn = await callFunction('respondToAssistanceAssignment', {
    sessionToken: helperToken, assignmentId: assigned2.body.result.assignmentId,
    decision: 'WITHDRAWN', residentConsentConfirmed: true, commandId: requestId(),
  });
  assert.equal(withdrawn.body.result.state, 'WITHDRAWN');
  assert.equal((await readDocument('resident_profiles', targetId)).body.fields.needsAssistance.booleanValue, true);
  const directRead = await request('GET', documentUrl('assistance_assignments', assignmentId), {
    token: operatorA.idToken,
  });
  assert.notEqual(directRead.status, 200);
});
