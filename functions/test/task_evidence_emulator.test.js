const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getStorage } = require('firebase-admin/storage');
const { getFirestore } = require('firebase-admin/firestore');
const { hashJoinCode } = require('../src/resident_session_service');
const { responseDocumentId } = require('../src/task_response_service');
const { buildStoragePath } = require('../src/task_evidence_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const BUCKET_NAME = `${PROJECT_ID}.appspot.com`;
const PORTS = { auth: 9099, functions: 5001, firestore: 8080, storage: 9199 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const STORAGE_BASE = `http://${HOST}:${PORTS.storage}`;
const JPEG = fs.readFileSync(path.join(__dirname, 'fixtures', 'geotagged.jpg'));

async function request(method, url, { token, body, headers: additionalHeaders = {} } = {}) {
  const headers = { ...additionalHeaders };
  if (body != null && !('Content-Type' in headers)) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, {
    method,
    headers,
    ...(body == null ? {} : { body: typeof body === 'string' || Buffer.isBuffer(body)
      ? body : JSON.stringify(body) }),
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) { payload = text; }
  return { status: response.status, body: payload };
}

async function createAccount() {
  const number = crypto.randomUUID();
  const result = await request(
    'POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`,
    { body: {
      email: `evidence-${number}@example.invalid`,
      password: 'test-password-123',
      returnSecureToken: true,
    } },
  );
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}

function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}

function fields(record) {
  const result = {};
  for (const [key, value] of Object.entries(record)) {
    if (typeof value === 'string') result[key] = { stringValue: value };
    else if (typeof value === 'boolean') result[key] = { booleanValue: value };
    else if (Number.isInteger(value)) result[key] = { integerValue: String(value) };
    else if (value instanceof Date) result[key] = { timestampValue: value.toISOString() };
  }
  return result;
}

async function seedDocument(collection, id, record) {
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner', body: { fields: fields(record) },
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
  const response = await request(
    'POST', `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`,
    { body: { data } },
  );
  return response;
}

function randomRequestId() {
  return crypto.randomBytes(32).toString('base64url');
}

function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}

function responseRecord(rtId, taskId, residentId) {
  const responseId = responseDocumentId(rtId, taskId, residentId);
  return {
    responseId,
    taskId,
    rtId,
    residentId,
    participationState: 'JOINED',
    participationCommandHash: crypto.createHash('sha256').update('test-command').digest('hex'),
    completionState: 'NOT_SUBMITTED',
    completionNote: null,
    completionCommandHash: null,
    completionSubmittedAt: null,
    verifiedAt: null,
    verifiedByOperatorUid: null,
    verificationCommandHash: null,
    createdAt: new Date(),
    updatedAt: new Date(),
  };
}

function fieldValue(document, key) {
  const value = document.fields?.[key];
  return value?.stringValue ?? value?.timestampValue ?? null;
}

const adminApp = getApps().find((app) => app.name === '[DEFAULT]') ??
  initializeApp({ projectId: PROJECT_ID, storageBucket: BUCKET_NAME });
const adminBucket = getStorage(adminApp).bucket(BUCKET_NAME);

test('optional evidence is sanitized, RT-scoped, private, deletable, and not exposed as a URL', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-evidence-${suffix}`;
  const joinCode = `EV${suffix.slice(0, 14).toUpperCase()}`;
  const taskId = crypto.randomBytes(20).toString('hex');
  await seedCommunity(rtId, joinCode);
  const residentResponse = await callFunction('createResidentSession', {
    joinCode,
    nickname: 'Warga Uji',
    requestId: randomRequestId(),
  });
  assert.equal(residentResponse.status, 200, JSON.stringify(residentResponse.body));
  const resident = residentResponse.body.result;
  const responseId = responseDocumentId(rtId, taskId, resident.residentId);
  await seedDocument('task_campaigns', taskId, {
    campaignId: taskId,
    rtId,
    status: 'ACTIVE',
    deadline: new Date(Date.now() + 24 * 60 * 60 * 1000),
  });
  await seedDocument('task_responses', responseId, responseRecord(rtId, taskId, resident.residentId));

  const upload = await callFunction('uploadResidentTaskEvidence', {
    sessionToken: resident.sessionToken,
    taskId,
    requestId: randomRequestId(),
    imageBase64: JPEG.toString('base64'),
  });
  assert.equal(upload.status, 200, JSON.stringify(upload.body));
  const result = upload.body.result;
  assert.deepEqual(Object.keys(result).sort(), ['evidenceId', 'expiresAt']);
  assert.match(result.evidenceId, /^[a-f0-9]{40}$/u);
  assert.equal(typeof result.expiresAt, 'string');
  assert.equal(JSON.stringify(result).includes('https://'), false);

  const objectPath = buildStoragePath(rtId, taskId, resident.residentId, result.evidenceId);
  const file = adminBucket.file(objectPath);
  const [storedBytes] = await file.download();
  const imageMetadata = await sharp(storedBytes).metadata();
  assert.equal(imageMetadata.format, 'jpeg');
  assert.equal(imageMetadata.exif, undefined);
  const [storageMetadata] = await file.getMetadata();
  assert.equal(storageMetadata.contentType, 'image/jpeg');
  assert.equal(storageMetadata.cacheControl, 'private, no-store');
  assert.equal(storageMetadata.metadata.evidenceId, result.evidenceId);

  const directRead = await request(
    'GET', `${STORAGE_BASE}/v0/b/${encodeURIComponent(BUCKET_NAME)}/o/${encodeURIComponent(objectPath)}?alt=media`,
    { token: resident.idToken },
  );
  assert.equal(directRead.status, 403, JSON.stringify(directRead.body));
  const directWrite = await request(
    'POST', `${STORAGE_BASE}/v0/b/${encodeURIComponent(BUCKET_NAME)}/o?uploadType=media&name=${encodeURIComponent(`${objectPath}.forged`)}`,
    { token: resident.idToken, body: JPEG, headers: { 'Content-Type': 'image/jpeg' } },
  );
  assert.equal(directWrite.status, 403, JSON.stringify(directWrite.body));
  const directMetadataRead = await request(
    'GET', documentUrl('task_evidence', result.evidenceId), { token: resident.idToken },
  );
  assert.equal(directMetadataRead.status, 403, JSON.stringify(directMetadataRead.body));

  const evidenceDocument = await request('GET', documentUrl('task_evidence', result.evidenceId), {
    token: 'owner',
  });
  assert.equal(evidenceDocument.status, 200, JSON.stringify(evidenceDocument.body));
  assert.equal(fieldValue(evidenceDocument.body, 'status'), 'READY');
  assert.equal(fieldValue(evidenceDocument.body, 'storagePath'), objectPath);
  assert.equal('residentId' in evidenceDocument.body.fields, false);
  assert.equal(JSON.stringify(evidenceDocument.body).includes(resident.sessionToken), false);

  const completionCommandId = randomRequestId();
  const completionPayload = {
    sessionToken: resident.sessionToken,
    taskId,
    note: null,
    commandId: completionCommandId,
    evidenceId: result.evidenceId,
  };
  const completion = await callFunction('submitTaskCompletion', completionPayload);
  assert.equal(completion.status, 200, JSON.stringify(completion.body));
  assert.equal(completion.body.result.evidenceId, result.evidenceId);

  const operator = await createAccount();
  await seedDocument('operators', operator.localId, { rtId, role: 'KETUA_RT_RW', active: true });
  const pending = await request(
    'POST', `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/listPendingTaskVerifications`,
    { token: operator.idToken, body: { data: {} } },
  );
  assert.equal(pending.status, 200, JSON.stringify(pending.body));
  assert.ok(pending.body.result.items.some((item) => item.evidenceId === result.evidenceId));
  const privateImage = await request(
    'POST', `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/getTaskEvidenceForVerification`,
    { token: operator.idToken, body: { data: { evidenceId: result.evidenceId } } },
  );
  assert.equal(privateImage.status, 200, JSON.stringify(privateImage.body));
  assert.equal(privateImage.body.result.contentType, 'image/jpeg');
  assert.equal((await sharp(Buffer.from(privateImage.body.result.imageBase64, 'base64')).metadata()).exif,
    undefined);
  const unauthenticatedRead = await callFunction('getTaskEvidenceForVerification', {
    evidenceId: result.evidenceId,
  });
  assertError(unauthenticatedRead, 'PERMISSION_DENIED');

  const secondRt = `rt-evidence-other-${suffix}`;
  const secondJoinCode = `OT${suffix.slice(0, 14).toUpperCase()}`;
  await seedCommunity(secondRt, secondJoinCode);
  const otherResidentResponse = await callFunction('createResidentSession', {
    joinCode: secondJoinCode,
    nickname: 'Warga Lain',
    requestId: randomRequestId(),
  });
  assert.equal(otherResidentResponse.status, 200, JSON.stringify(otherResidentResponse.body));
  const otherOperator = await createAccount();
  await seedDocument('operators', otherOperator.localId, {
    rtId: secondRt,
    role: 'KETUA_RT_RW',
    active: true,
  });
  const crossRtRead = await request(
    'POST', `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/getTaskEvidenceForVerification`,
    { token: otherOperator.idToken, body: { data: { evidenceId: result.evidenceId } } },
  );
  assertError(crossRtRead, 'PERMISSION_DENIED');
  const crossRtDelete = await callFunction('deleteResidentTaskEvidence', {
    sessionToken: otherResidentResponse.body.result.sessionToken,
    evidenceId: result.evidenceId,
    commandId: randomRequestId(),
  });
  assertError(crossRtDelete, 'PERMISSION_DENIED');

  const deletionRequest = {
    sessionToken: resident.sessionToken,
    evidenceId: result.evidenceId,
    commandId: randomRequestId(),
  };
  const deleted = await callFunction('deleteResidentTaskEvidence', deletionRequest);
  assert.equal(deleted.status, 200, JSON.stringify(deleted.body));
  const deleteReplay = await callFunction('deleteResidentTaskEvidence', deletionRequest);
  assert.equal(deleteReplay.status, 200, JSON.stringify(deleteReplay.body));
  await assert.rejects(file.getMetadata(), (error) => error.code === 404);
  const evidenceAfterDelete = await request('GET', documentUrl('task_evidence', result.evidenceId), {
    token: 'owner',
  });
  assert.equal(fieldValue(evidenceAfterDelete.body, 'status'), 'DELETED');
  assert.equal('storagePath' in evidenceAfterDelete.body.fields, false);
  const responseAfterDelete = await request('GET', documentUrl('task_responses', responseId), {
    token: 'owner',
  });
  assert.equal('evidenceId' in responseAfterDelete.body.fields, false);
  const completionReplay = await callFunction('submitTaskCompletion', completionPayload);
  assert.equal(completionReplay.status, 200, JSON.stringify(completionReplay.body));
  assert.equal(completionReplay.body.result.completionState, 'PENDING_RT_VERIFICATION');
  assert.equal(completionReplay.body.result.evidenceId, null);

  const retentionTaskId = crypto.randomBytes(20).toString('hex');
  const retentionResponseId = responseDocumentId(rtId, retentionTaskId, resident.residentId);
  await seedDocument('task_campaigns', retentionTaskId, {
    campaignId: retentionTaskId,
    rtId,
    status: 'ACTIVE',
    deadline: new Date(Date.now() + 24 * 60 * 60 * 1000),
  });
  await seedDocument('task_responses', retentionResponseId,
    responseRecord(rtId, retentionTaskId, resident.residentId));
  const retentionUpload = await callFunction('uploadResidentTaskEvidence', {
    sessionToken: resident.sessionToken,
    taskId: retentionTaskId,
    requestId: randomRequestId(),
    imageBase64: JPEG.toString('base64'),
  });
  assert.equal(retentionUpload.status, 200, JSON.stringify(retentionUpload.body));
  const retentionEvidenceId = retentionUpload.body.result.evidenceId;
  const retentionPath = buildStoragePath(rtId, retentionTaskId, resident.residentId,
    retentionEvidenceId);
  const firestore = getFirestore(adminApp);
  await firestore.collection('task_evidence').doc(retentionEvidenceId).update({
    expiresAt: new Date(Date.now() - 31 * 24 * 60 * 60 * 1000),
  });
  const scheduledCleanup = require('../src/index').deleteExpiredTaskEvidence;
  await scheduledCleanup.run({ scheduleTime: new Date().toISOString() });
  await assert.rejects(adminBucket.file(retentionPath).getMetadata(),
    (error) => error.code === 404);
  const retentionRecord = await firestore.collection('task_evidence')
    .doc(retentionEvidenceId).get();
  assert.equal(retentionRecord.data().status, 'DELETED');
  assert.equal('expiresAt' in retentionRecord.data(), false);
});
