const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode, hashSessionToken } = require('../src/resident_session_service');
const { responseDocumentId } = require('../src/task_response_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, functions: 5001, firestore: 8080 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const DEADLINE = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

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

async function createAccount({ anonymous = false } = {}) {
  const number = crypto.randomUUID();
  const body = { returnSecureToken: true };
  if (!anonymous) {
    body.email = `task-response-${number}@example.invalid`;
    body.password = 'test-password-123';
  }
  const result = await request(
    'POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, { body },
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

async function seedOperator(uid, rtId, role = 'KETUA_RT_RW') {
  await seedDocument('operators', uid, { rtId, role, active: true });
}

async function seedCommunity(rtId, joinCode) {
  await seedDocument('rt_communities', rtId, {
    displayName: `Komunitas ${rtId}`,
    rtLabel: 'RT Uji',
    joinCodeHash: hashJoinCode(joinCode),
    joinCodeActive: true,
  });
}

async function seedTemplate(templateId) {
  await seedDocument('task_templates', `${templateId}_v1`, {
    templateId,
    version: 1,
    title: 'Siapkan perlengkapan keluarga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting di tempat yang mudah dijangkau.',
    safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik basah.',
    estimatedDurationMinutes: 30,
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'trusted-reviewer',
    reviewedAt: new Date(),
  });
}

async function callFunction(name, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`,
    { method: 'POST', headers, body: JSON.stringify({ data }) },
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

test('resident task participation, completion, RT verification, recap, and access remain scoped and replay-safe', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-response-a-${suffix}`;
  const rtB = `rt-response-b-${suffix}`;
  const joinCodeA = `JA${suffix.slice(0, 14).toUpperCase()}`;
  const joinCodeB = `JB${suffix.slice(0, 14).toUpperCase()}`;
  const templateId = `phase3_${suffix.slice(0, 20)}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  const anonymous = await createAccount({ anonymous: true });
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtB);
  await seedOperator(anonymous.localId, rtA);
  await seedCommunity(rtA, joinCodeA);
  await seedCommunity(rtB, joinCodeB);
  await seedTemplate(templateId);

  const listedTemplates = await callFunction(
    'listApprovedTaskTemplates', {}, operatorA.idToken,
  );
  assert.equal(listedTemplates.status, 200, JSON.stringify(listedTemplates.body));
  assert.ok(listedTemplates.body.result.templates.some((item) => item.templateId === templateId));
  const draftResponse = await callFunction('createTaskDraft', {
    templateId,
    version: 1,
    deadline: DEADLINE,
    locationReference: 'Balai warga',
    requestId: randomRequestId(),
  }, operatorA.idToken);
  assert.equal(draftResponse.status, 200, JSON.stringify(draftResponse.body));
  const taskId = draftResponse.body.result.campaignId;
  const activation = await callFunction('activateTaskCampaign', {
    campaignId: taskId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assert.equal(activation.status, 200, JSON.stringify(activation.body));
  assert.equal(activation.body.result.status, 'ACTIVE');

  const residentA = await createResident(joinCodeA, 'Sari');
  const residentB = await createResident(joinCodeA, 'Budi');
  const residentC = await createResident(joinCodeB, 'Tini');
  const residentD = await createResident(joinCodeA, 'Raka');
  const activeA = await callFunction('listResidentActiveTasks', {
    sessionToken: residentA.sessionToken,
  });
  assert.equal(activeA.status, 200, JSON.stringify(activeA.body));
  assert.equal(activeA.body.result.items.length, 1);
  assert.equal(activeA.body.result.items[0].taskId, taskId);
  assert.equal(activeA.body.result.isPartial, false);
  assert.equal(activeA.body.result.items[0].participationState, 'UNRESPONDED');
  assert.equal(activeA.body.result.items[0].templateSnapshot.safetyInstruction,
    'Jangan mendekati air banjir atau instalasi listrik basah.');
  assert.equal('residentId' in activeA.body.result.items[0], false);
  assert.equal('completionNote' in activeA.body.result.items[0], true);

  const activeB = await callFunction('listResidentActiveTasks', {
    sessionToken: residentC.sessionToken,
  });
  assert.equal(activeB.status, 200, JSON.stringify(activeB.body));
  assert.deepEqual(activeB.body.result.items, []);
  assert.equal(activeB.body.result.isPartial, false);
  const forgedScope = await callFunction('listResidentActiveTasks', {
    sessionToken: residentA.sessionToken,
    rtId: rtB,
  });
  assertError(forgedScope, 'INVALID_ARGUMENT');
  const invalidSession = await callFunction('listResidentActiveTasks', {
    sessionToken: residentC.sessionToken,
    taskId,
  });
  assertError(invalidSession, 'INVALID_ARGUMENT');

  const joinCommand = randomRequestId();
  const join = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentA.sessionToken,
    taskId,
    choice: 'JOINED',
    commandId: joinCommand,
  });
  assert.equal(join.status, 200, JSON.stringify(join.body));
  assert.equal(join.body.result.participationState, 'JOINED');
  const joinReplay = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentA.sessionToken,
    taskId,
    choice: 'JOINED',
    commandId: joinCommand,
  });
  assert.equal(joinReplay.status, 200, JSON.stringify(joinReplay.body));
  const oppositeChoice = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentA.sessionToken,
    taskId,
    choice: 'DECLINED',
    commandId: randomRequestId(),
  });
  assertError(oppositeChoice, 'FAILED_PRECONDITION');
  const residentBIsolation = await callFunction('listResidentActiveTasks', {
    sessionToken: residentB.sessionToken,
  });
  assert.equal(residentBIsolation.status, 200, JSON.stringify(residentBIsolation.body));
  assert.equal(
    residentBIsolation.body.result.items[0].participationState,
    'UNRESPONDED',
  );
  const crossRtChoice = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentC.sessionToken,
    taskId,
    choice: 'JOINED',
    commandId: randomRequestId(),
  });
  assertError(crossRtChoice, 'PERMISSION_DENIED');

  const decline = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentB.sessionToken,
    taskId,
    choice: 'DECLINED',
    commandId: randomRequestId(),
  });
  assert.equal(decline.status, 200, JSON.stringify(decline.body));
  assert.equal(decline.body.result.participationState, 'DECLINED');
  const declinedCompletion = await callFunction('submitTaskCompletion', {
    sessionToken: residentB.sessionToken,
    taskId,
    note: null,
    commandId: randomRequestId(),
  });
  assertError(declinedCompletion, 'FAILED_PRECONDITION');

  const raceCommands = [randomRequestId(), randomRequestId()];
  const racingChoices = await Promise.all([
    callFunction('recordResidentTaskResponse', {
      sessionToken: residentD.sessionToken,
      taskId,
      choice: 'JOINED',
      commandId: raceCommands[0],
    }),
    callFunction('recordResidentTaskResponse', {
      sessionToken: residentD.sessionToken,
      taskId,
      choice: 'DECLINED',
      commandId: raceCommands[1],
    }),
  ]);
  assert.equal(racingChoices.filter((item) => item.status === 200).length, 1,
    JSON.stringify(racingChoices));
  assert.equal(racingChoices.filter((item) => item.body.error?.status === 'FAILED_PRECONDITION').length, 1,
    JSON.stringify(racingChoices));

  const completionCommand = randomRequestId();
  const completionPayload = {
    sessionToken: residentA.sessionToken,
    taskId,
    note: 'Perlengkapan sudah disiapkan.',
    commandId: completionCommand,
  };
  const concurrentCompletions = await Promise.all([
    callFunction('submitTaskCompletion', completionPayload),
    callFunction('submitTaskCompletion', completionPayload),
  ]);
  assert.ok(concurrentCompletions.every((item) => item.status === 200),
    JSON.stringify(concurrentCompletions));
  assert.ok(concurrentCompletions.every((item) =>
    item.body.result.completionState === 'PENDING_RT_VERIFICATION'));
  const changedCompletionPayload = await callFunction('submitTaskCompletion', {
    ...completionPayload,
    note: 'Catatan berbeda.',
  });
  assertError(changedCompletionPayload, 'FAILED_PRECONDITION');
  const addressNote = await callFunction('submitTaskCompletion', {
    ...completionPayload,
    note: 'Alamat Jalan Merdeka 10',
    commandId: randomRequestId(),
  });
  assertError(addressNote, 'INVALID_ARGUMENT');

  const responseId = responseDocumentId(rtA, taskId, residentA.residentId);
  const responseDocument = await request('GET', documentUrl('task_responses', responseId), {
    token: 'owner',
  });
  assert.equal(responseDocument.status, 200, JSON.stringify(responseDocument.body));
  const stored = responseDocument.body.fields;
  assert.equal(stored.participationState.stringValue, 'JOINED');
  assert.equal(stored.completionState.stringValue, 'PENDING_RT_VERIFICATION');
  assert.equal(stored.residentId.stringValue, residentA.residentId);
  assert.equal(stored.participationCommandHash.stringValue,
    crypto.createHash('sha256').update(joinCommand).digest('hex'));
  assert.equal(stored.completionCommandHash.stringValue,
    crypto.createHash('sha256').update(completionCommand).digest('hex'));
  assert.equal(JSON.stringify(stored).includes(residentA.sessionToken), false);
  assert.equal(JSON.stringify(stored).includes(completionCommand), false);
  for (const forbidden of ['nik', 'fullAddress', 'latitude', 'longitude', 'gps', 'sessionToken', 'rawCommandId']) {
    assert.equal(Object.keys(stored).some((key) => key.toLowerCase().includes(forbidden.toLowerCase())),
      false, `forbidden response field ${forbidden}`);
  }
  const sessionHash = hashSessionToken(residentA.sessionToken);
  const storedSession = await request('GET', documentUrl('resident_sessions', sessionHash), {
    token: 'owner',
  });
  assert.equal(storedSession.status, 200, JSON.stringify(storedSession.body));
  assert.equal(JSON.stringify(storedSession.body.fields).includes(residentA.sessionToken), false);

  const pendingA = await callFunction('listPendingTaskVerifications', {}, operatorA.idToken);
  assert.equal(pendingA.status, 200, JSON.stringify(pendingA.body));
  assert.equal(pendingA.body.result.items.length, 1);
  assert.equal(pendingA.body.result.items[0].responseId, responseId);
  assert.equal(pendingA.body.result.items[0].nickname, 'Sari');
  const pendingB = await callFunction('listPendingTaskVerifications', {}, operatorB.idToken);
  assert.equal(pendingB.status, 200, JSON.stringify(pendingB.body));
  assert.deepEqual(pendingB.body.result.items, []);
  assert.equal(pendingB.body.result.isPartial, false);
  const anonymousVerify = await callFunction('verifyTaskCompletion', {
    responseId,
    commandId: randomRequestId(),
  }, anonymous.idToken);
  assertError(anonymousVerify, 'PERMISSION_DENIED');
  const crossRtVerify = await callFunction('verifyTaskCompletion', {
    responseId,
    commandId: randomRequestId(),
  }, operatorB.idToken);
  assertError(crossRtVerify, 'PERMISSION_DENIED');

  const verifyCommand = randomRequestId();
  const verifyPayload = { responseId, commandId: verifyCommand };
  const concurrentVerifications = await Promise.all([
    callFunction('verifyTaskCompletion', verifyPayload, operatorA.idToken),
    callFunction('verifyTaskCompletion', verifyPayload, operatorA.idToken),
  ]);
  assert.ok(concurrentVerifications.every((item) => item.status === 200),
    JSON.stringify(concurrentVerifications));
  assert.ok(concurrentVerifications.every((item) =>
    item.body.result.completionState === 'VERIFIED_COMPLETE'));
  const conflictingVerification = await callFunction('verifyTaskCompletion', {
    responseId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assertError(conflictingVerification, 'FAILED_PRECONDITION');
  const audit = await request('GET', documentUrl('task_audit_events', `${responseId}_verified`), {
    token: 'owner',
  });
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.action.stringValue, 'TASK_COMPLETION_VERIFIED');
  assert.equal(audit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(JSON.stringify(audit.body.fields).includes(residentA.sessionToken), false);

  const pendingAfterVerify = await callFunction(
    'listPendingTaskVerifications', {}, operatorA.idToken,
  );
  assert.deepEqual(pendingAfterVerify.body.result.items, []);
  const taskAfterVerify = await callFunction('listResidentActiveTasks', {
    sessionToken: residentA.sessionToken,
  });
  assert.equal(taskAfterVerify.body.result.items[0].completionState, 'VERIFIED_COMPLETE');
  const recap = await callFunction('getTaskResponseRecap', { taskId }, operatorA.idToken);
  assert.equal(recap.status, 200, JSON.stringify(recap.body));
  assert.equal(recap.body.result.recordedResponseCount, 3);
  assert.equal(recap.body.result.joinedCount + recap.body.result.declinedCount, 3);
  assert.equal(recap.body.result.verifiedCompleteCount, 1);
  assert.equal('nonResponseCount' in recap.body.result, false);

  const taskClientRead = await request('GET', documentUrl('task_responses', responseId), {
    token: anonymous.idToken,
  });
  assert.notEqual(taskClientRead.status, 200);
  const taskClientWrite = await request('PATCH', documentUrl('task_responses', 'forged-response'), {
    token: anonymous.idToken,
    body: { fields: fields({ rtId: rtA, residentId: residentA.residentId }) },
  });
  assert.notEqual(taskClientWrite.status, 200);
});
