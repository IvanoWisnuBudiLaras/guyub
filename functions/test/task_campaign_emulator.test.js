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
const now = new Date();
const DEADLINE = new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString();

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
    body.email = `task-operator-${number}@example.invalid`;
    body.password = 'test-password-123';
  }
  const result = await request(
    'POST',
    `${AUTH_BASE}/accounts:signUp?key=fake-api-key`,
    { body },
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
    token: 'owner',
    body: { fields: fields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

async function seedOperator(uid, {
  rtId = 'rt-task-a', role = 'KETUA_RT_RW', active = true,
} = {}) {
  await seedDocument('operators', uid, { rtId, role, active });
}

async function seedCommunity(rtId, joinCode) {
  await seedDocument('rt_communities', rtId, {
    displayName: `Komunitas ${rtId}`,
    rtLabel: 'RT Uji',
    joinCodeHash: hashJoinCode(joinCode),
    joinCodeActive: true,
  });
}

async function seedTemplate({
  templateId = 'safe_household_prep',
  version = 1,
  title = 'Persiapan rumah tangga',
  category = 'HOUSEHOLD_PREPARATION',
  coreInstruction = 'Simpan dokumen penting di wadah yang mudah dijangkau.',
  safetyInstruction = 'Jangan mendekati air banjir atau instalasi listrik yang basah.',
  estimatedDurationMinutes = 30,
  enabled = true,
  reviewStatus = 'approved',
  reviewedBy = 'trusted-reviewer',
  reviewedAt = new Date(),
} = {}) {
  await seedDocument('task_templates', `${templateId}_v${version}`, {
    templateId,
    version,
    title,
    category,
    coreInstruction,
    safetyInstruction,
    estimatedDurationMinutes,
    enabled,
    reviewStatus,
    reviewedBy,
    reviewedAt,
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

async function updateDocumentFields(collection, id, record) {
  const masks = Object.keys(record)
    .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`).join('&');
  const result = await request('PATCH', `${documentUrl(collection, id)}?${masks}`, {
    token: 'owner',
    body: { fields: fields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

async function readDocument(collection, id) {
  return request('GET', documentUrl(collection, id), { token: 'owner' });
}

function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}

test('operator task callables enforce RT scope, reviewed templates, locked content and replay safety', async () => {
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  const inactive = await createAccount();
  const invalidRole = await createAccount();
  const noMembership = await createAccount();
  const replacementOperator = await createAccount();
  const resident = await createAccount({ anonymous: true });
  await seedOperator(operatorA.localId, { rtId: 'rt-task-a' });
  await seedOperator(operatorB.localId, { rtId: 'rt-task-b' });
  await seedOperator(inactive.localId, { rtId: 'rt-task-a', active: false });
  await seedOperator(invalidRole.localId, { rtId: 'rt-task-a', role: 'RESIDENT' });
  await seedOperator(resident.localId, { rtId: 'rt-task-a' });

  await seedTemplate();
  await seedTemplate({ templateId: 'template_pending', reviewStatus: 'pending' });
  await seedTemplate({ templateId: 'template_disabled', enabled: false });
  await seedTemplate({ templateId: 'template_missing_safety', safetyInstruction: '' });
  await seedTemplate({ templateId: 'template_mutable' });

  const unauthorizedList = await callFunction('listApprovedTaskTemplates', {});
  assertError(unauthorizedList, 'PERMISSION_DENIED');
  const residentList = await callFunction('listApprovedTaskTemplates', {}, resident.idToken);
  assertError(residentList, 'PERMISSION_DENIED');
  const missingMembershipList = await callFunction(
    'listApprovedTaskTemplates', {}, noMembership.idToken,
  );
  assertError(missingMembershipList, 'PERMISSION_DENIED');
  const inactiveList = await callFunction('listApprovedTaskTemplates', {}, inactive.idToken);
  assertError(inactiveList, 'PERMISSION_DENIED');
  const invalidRoleList = await callFunction('listApprovedTaskTemplates', {}, invalidRole.idToken);
  assertError(invalidRoleList, 'PERMISSION_DENIED');

  const listed = await callFunction('listApprovedTaskTemplates', {}, operatorA.idToken);
  assert.equal(listed.status, 200, JSON.stringify(listed.body));
  const templates = listed.body.result.templates;
  assert.deepEqual(templates.map((item) => item.templateId).sort(), [
    'safe_household_prep',
    'template_mutable',
  ].sort());
  assert.equal('reviewedBy' in templates[0], false);
  assert.ok(templates.every((item) => typeof item.safetyInstruction === 'string' &&
    item.safetyInstruction.trim().length > 0));

  const requestId = randomRequestId();
  const draftPayload = {
    templateId: 'safe_household_prep',
    version: 1,
    deadline: DEADLINE,
    locationReference: 'COMMUNITY_GENERAL_AREA',
    requestId,
  };
  const draftResponse = await callFunction('createTaskDraft', draftPayload, operatorA.idToken);
  assert.equal(draftResponse.status, 200, JSON.stringify(draftResponse.body));
  const draft = draftResponse.body.result;
  assert.equal(draft.status, 'DRAFT');
  assert.equal(draft.rtId, 'rt-task-a');
  assert.equal(draft.templateSnapshot.safetyInstruction,
    'Jangan mendekati air banjir atau instalasi listrik yang basah.');
  assert.equal(draft.templateSnapshot.estimatedDurationMinutes, 30);

  const unsafeDraftText = await callFunction('createTaskDraft', {
    ...draftPayload,
    requestId: randomRequestId(),
    additionalNote: 'Masuk ke saluran air untuk membersihkan sampah',
  }, operatorA.idToken);
  assertError(unsafeDraftText, 'INVALID_ARGUMENT');
  const unsafeLocation = await callFunction('createTaskDraft', {
    ...draftPayload,
    requestId: randomRequestId(),
    locationReference: 'Masuk ke saluran air untuk membersihkan sampah',
  }, operatorA.idToken);
  assertError(unsafeLocation, 'INVALID_ARGUMENT');

  const storedDraft = await readDocument('task_campaigns', draft.campaignId);
  assert.equal(storedDraft.status, 200, JSON.stringify(storedDraft.body));
  assert.equal(storedDraft.body.fields.rtId.stringValue, 'rt-task-a');
  assert.equal(storedDraft.body.fields.status.stringValue, 'DRAFT');
  assert.equal(storedDraft.body.fields.createdByOperatorUid.stringValue, operatorA.localId);
  assert.equal(storedDraft.body.fields.templateSnapshot.mapValue.fields.safetyInstruction.stringValue,
    draft.templateSnapshot.safetyInstruction);

  const retryDraft = await callFunction('createTaskDraft', draftPayload, operatorA.idToken);
  assert.equal(retryDraft.status, 200, JSON.stringify(retryDraft.body));
  assert.equal(retryDraft.body.result.campaignId, draft.campaignId);
  const changedRetry = await callFunction('createTaskDraft', {
    ...draftPayload,
    deadline: new Date(new Date(DEADLINE).getTime() + 1000).toISOString(),
  }, operatorA.idToken);
  assertError(changedRetry, 'ALREADY_EXISTS');

  for (const forged of [
    { ...draftPayload, coreInstruction: 'Unsafe client-authored task' },
    { ...draftPayload, safetyInstruction: 'Forged safety text' },
    { ...draftPayload, rtId: 'rt-task-b' },
    { ...draftPayload, operatorUid: operatorB.localId },
  ]) {
    assertError(await callFunction('createTaskDraft', forged, operatorA.idToken), 'INVALID_ARGUMENT');
  }
  for (const templateId of ['template_pending', 'template_disabled', 'template_missing_safety']) {
    const rejected = await callFunction('createTaskDraft', {
      ...draftPayload,
      templateId,
      requestId: randomRequestId(),
    }, operatorA.idToken);
    assertError(rejected, 'FAILED_PRECONDITION');
  }
  const coordinateLocation = await callFunction('createTaskDraft', {
    ...draftPayload,
    requestId: randomRequestId(),
    locationReference: '-6.123456, 106.123456',
  }, operatorA.idToken);
  assertError(coordinateLocation, 'INVALID_ARGUMENT');
  const residentialLocation = await callFunction('createTaskDraft', {
    ...draftPayload,
    requestId: randomRequestId(),
    locationReference: 'Jalan Mawar No. 12',
  }, operatorA.idToken);
  assertError(residentialLocation, 'INVALID_ARGUMENT');

  const commandId = randomRequestId();
  const crossRtActivation = await callFunction('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId,
  }, operatorB.idToken);
  assertError(crossRtActivation, 'PERMISSION_DENIED');
  const forgedActivation = await callFunction('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId,
    rtId: 'rt-task-a',
    operatorUid: operatorA.localId,
    coreInstruction: 'replace locked instructions',
  }, operatorA.idToken);
  assertError(forgedActivation, 'INVALID_ARGUMENT');
  const inactiveActivation = await callFunction('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId,
  }, inactive.idToken);
  assertError(inactiveActivation, 'PERMISSION_DENIED');
  const residentActivation = await callFunction('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId,
  }, resident.idToken);
  assertError(residentActivation, 'PERMISSION_DENIED');

  const activationPayload = { campaignId: draft.campaignId, commandId };
  const concurrent = await Promise.all([
    callFunction('activateTaskCampaign', activationPayload, operatorA.idToken),
    callFunction('activateTaskCampaign', activationPayload, operatorA.idToken),
  ]);
  for (const result of concurrent) {
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.equal(result.body.result.status, 'ACTIVE');
    assert.equal(result.body.result.campaignId, draft.campaignId);
  }
  const replay = await callFunction('activateTaskCampaign', activationPayload, operatorA.idToken);
  assert.equal(replay.status, 200, JSON.stringify(replay.body));
  const differentCommand = await callFunction('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assertError(differentCommand, 'FAILED_PRECONDITION');

  const foreignDraftResponse = await callFunction('createTaskDraft', {
    ...draftPayload,
    requestId: randomRequestId(),
  }, operatorB.idToken);
  assert.equal(foreignDraftResponse.status, 200, JSON.stringify(foreignDraftResponse.body));
  const foreignTaskId = foreignDraftResponse.body.result.campaignId;
  const foreignActivation = await callFunction('activateTaskCampaign', {
    campaignId: foreignTaskId,
    commandId: randomRequestId(),
  }, operatorB.idToken);
  assert.equal(foreignActivation.status, 200, JSON.stringify(foreignActivation.body));

  const unauthenticatedActiveList = await callFunction('listActiveTaskCampaigns', {});
  assertError(unauthenticatedActiveList, 'PERMISSION_DENIED');
  const residentActiveList = await callFunction(
    'listActiveTaskCampaigns', {}, resident.idToken,
  );
  assertError(residentActiveList, 'PERMISSION_DENIED');
  const inactiveActiveList = await callFunction(
    'listActiveTaskCampaigns', {}, inactive.idToken,
  );
  assertError(inactiveActiveList, 'PERMISSION_DENIED');
  const activeListA = await callFunction('listActiveTaskCampaigns', {}, operatorA.idToken);
  assert.equal(activeListA.status, 200, JSON.stringify(activeListA.body));
  assert.deepEqual(activeListA.body.result.tasks.map((item) => item.taskId), [draft.campaignId]);
  const listedTask = activeListA.body.result.tasks[0];
  assert.deepEqual(Object.keys(listedTask).sort(), [
    'deadline', 'locationReference', 'taskId', 'templateSnapshot',
  ]);
  assert.equal(listedTask.templateSnapshot.title, 'Persiapan rumah tangga');
  assert.equal('rtId' in listedTask, false);
  const activeListB = await callFunction('listActiveTaskCampaigns', {}, operatorB.idToken);
  assert.equal(activeListB.status, 200, JSON.stringify(activeListB.body));
  assert.deepEqual(activeListB.body.result.tasks.map((item) => item.taskId), [foreignTaskId]);

  const cancelPayload = { taskId: draft.campaignId, commandId: randomRequestId() };
  const crossRtCancel = await callFunction('cancelTaskCampaign', cancelPayload, operatorB.idToken);
  assertError(crossRtCancel, 'PERMISSION_DENIED');
  const inactiveCancel = await callFunction('cancelTaskCampaign', cancelPayload, inactive.idToken);
  assertError(inactiveCancel, 'PERMISSION_DENIED');
  const missingCancel = await callFunction('cancelTaskCampaign', {
    taskId: '0'.repeat(40), commandId: cancelPayload.commandId,
  }, operatorB.idToken);
  assertError(missingCancel, 'PERMISSION_DENIED');
  assert.equal(missingCancel.body.error.status, crossRtCancel.body.error.status);
  assert.equal(missingCancel.body.error.message, crossRtCancel.body.error.message);
  assertError(await callFunction('cancelTaskCampaign', {
    ...cancelPayload, rtId: 'rt-task-a',
  }, operatorA.idToken), 'INVALID_ARGUMENT');
  assertError(await callFunction('cancelTaskCampaign', {
    ...cancelPayload, actorUid: operatorA.localId,
  }, operatorA.idToken), 'INVALID_ARGUMENT');
  assertError(await callFunction('cancelTaskCampaign', cancelPayload, resident.idToken),
    'PERMISSION_DENIED');

  const joinCode = `JC${crypto.randomBytes(8).toString('hex').toUpperCase()}`;
  await seedCommunity('rt-task-a', joinCode);
  const residentSession = await callFunction('createResidentSession', {
    joinCode,
    nickname: 'Sari',
    requestId: randomRequestId(),
  });
  assert.equal(residentSession.status, 200, JSON.stringify(residentSession.body));
  const residentTasksBeforeCancel = await callFunction('listResidentActiveTasks', {
    sessionToken: residentSession.body.result.sessionToken,
  });
  assert.equal(residentTasksBeforeCancel.status, 200,
    JSON.stringify(residentTasksBeforeCancel.body));
  assert.deepEqual(residentTasksBeforeCancel.body.result.items.map((item) => item.taskId),
    [draft.campaignId]);

  const historyJoin = await callFunction('recordResidentTaskResponse', {
    sessionToken: residentSession.body.result.sessionToken,
    taskId: draft.campaignId,
    choice: 'JOINED',
    commandId: randomRequestId(),
  });
  assert.equal(historyJoin.status, 200, JSON.stringify(historyJoin.body));
  const historyCompletion = await callFunction('submitTaskCompletion', {
    sessionToken: residentSession.body.result.sessionToken,
    taskId: draft.campaignId,
    note: null,
    commandId: randomRequestId(),
  });
  assert.equal(historyCompletion.status, 200, JSON.stringify(historyCompletion.body));
  assert.equal(historyCompletion.body.result.completionState, 'PENDING_RT_VERIFICATION');
  const historyPending = await callFunction('listPendingTaskVerifications', {}, operatorA.idToken);
  assert.equal(historyPending.status, 200, JSON.stringify(historyPending.body));
  const historyPendingResponse = historyPending.body.result.items.find(
    (item) => item.taskId === draft.campaignId,
  );
  assert.ok(historyPendingResponse);
  const historyResponseId = historyPendingResponse.responseId;
  const historyVerification = await callFunction('verifyTaskCompletion', {
    responseId: historyResponseId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assert.equal(historyVerification.status, 200, JSON.stringify(historyVerification.body));
  assert.equal(historyVerification.body.result.completionState, 'VERIFIED_COMPLETE');

  const cancellationResults = await Promise.all([
    callFunction('cancelTaskCampaign', cancelPayload, operatorA.idToken),
    callFunction('cancelTaskCampaign', cancelPayload, operatorA.idToken),
  ]);
  for (const result of cancellationResults) {
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.deepEqual(result.body.result, { taskId: draft.campaignId, status: 'CANCELLED' });
  }
  const cancelReplay = await callFunction('cancelTaskCampaign', cancelPayload, operatorA.idToken);
  assert.equal(cancelReplay.status, 200, JSON.stringify(cancelReplay.body));
  const conflictingCancel = await callFunction('cancelTaskCampaign', {
    taskId: draft.campaignId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assertError(conflictingCancel, 'FAILED_PRECONDITION');

  const cancelledTask = await readDocument('task_campaigns', draft.campaignId);
  assert.equal(cancelledTask.status, 200, JSON.stringify(cancelledTask.body));
  assert.equal(cancelledTask.body.fields.status.stringValue, 'CANCELLED');
  assert.equal(cancelledTask.body.fields.cancelledByOperatorUid.stringValue, operatorA.localId);
  assert.equal(cancelledTask.body.fields.cancellationCommandHash.stringValue,
    crypto.createHash('sha256').update(cancelPayload.commandId).digest('hex'));
  assert.equal(cancelledTask.body.fields.commandId, undefined);
  const cancellationAuditId = `${draft.campaignId}_cancelled`;
  const cancellationAudit = await readDocument('task_audit_events', cancellationAuditId);
  assert.equal(cancellationAudit.status, 200, JSON.stringify(cancellationAudit.body));
  assert.equal(cancellationAudit.body.fields.action.stringValue, 'CAMPAIGN_CANCELLED');
  assert.equal(cancellationAudit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(cancellationAudit.body.fields.commandHash.stringValue,
    crypto.createHash('sha256').update(cancelPayload.commandId).digest('hex'));
  assert.equal(cancellationAudit.body.fields.commandId, undefined);
  const auditEvents = await request('GET', `${FIRESTORE_BASE}/task_audit_events?pageSize=100`, {
    token: 'owner',
  });
  assert.equal(auditEvents.status, 200, JSON.stringify(auditEvents.body));
  assert.equal((auditEvents.body.documents ?? []).filter((document) =>
    document.name.endsWith(`/${cancellationAuditId}`)).length, 1);

  const listAfterCancel = await callFunction('listActiveTaskCampaigns', {}, operatorA.idToken);
  assert.equal(listAfterCancel.status, 200, JSON.stringify(listAfterCancel.body));
  assert.deepEqual(listAfterCancel.body.result.tasks, []);
  const residentTasksAfterCancel = await callFunction('listResidentActiveTasks', {
    sessionToken: residentSession.body.result.sessionToken,
  });
  assert.equal(residentTasksAfterCancel.status, 200, JSON.stringify(residentTasksAfterCancel.body));
  assert.deepEqual(residentTasksAfterCancel.body.result.items, []);

  const historyTemplateId = 'history_safe_prep';
  await seedTemplate({ templateId: historyTemplateId });
  const additionalHistoryTaskIds = [];
  for (let index = 0; index < 2; index += 1) {
    const historyDraft = await callFunction('createTaskDraft', {
      ...draftPayload,
      templateId: historyTemplateId,
      requestId: randomRequestId(),
    }, operatorA.idToken);
    assert.equal(historyDraft.status, 200, JSON.stringify(historyDraft.body));
    const taskId = historyDraft.body.result.campaignId;
    const historyActivation = await callFunction('activateTaskCampaign', {
      campaignId: taskId,
      commandId: randomRequestId(),
    }, operatorA.idToken);
    assert.equal(historyActivation.status, 200, JSON.stringify(historyActivation.body));
    additionalHistoryTaskIds.push(taskId);
  }

  // Equal activation times exercise the campaignId DESC tie-breaker across page boundaries.
  const sharedActivatedAt = new Date('2026-10-04T09:00:00.000Z');
  for (const taskId of [draft.campaignId, ...additionalHistoryTaskIds]) {
    await updateDocumentFields('task_campaigns', taskId, { activatedAt: sharedActivatedAt });
  }
  const expectedHistoryIds = [draft.campaignId, ...additionalHistoryTaskIds].sort().reverse();
  const pagedHistoryIds = [];
  const pagedHistoryTasks = [];
  let historyCursor;
  do {
    const historyPage = await callFunction('listRtTaskHistory', {
      pageSize: 1,
      ...(historyCursor == null ? {} : { cursor: historyCursor }),
    }, operatorA.idToken);
    assert.equal(historyPage.status, 200, JSON.stringify(historyPage.body));
    const historyResult = historyPage.body.result;
    assert.equal(historyResult.tasks.length, 1);
    const task = historyResult.tasks[0];
    assert.deepEqual(Object.keys(task).sort(), [
      'activatedAt', 'cancelledAt', 'closedAt', 'deadline', 'locationReference', 'status',
      'taskId', 'templateSnapshot',
    ]);
    assert.equal(task.activatedAt, sharedActivatedAt.toISOString());
    assert.ok(['ACTIVE', 'CLOSED', 'CANCELLED'].includes(task.status));
    assert.equal('rtId' in task, false);
    assert.equal('actorUid' in task, false);
    pagedHistoryIds.push(task.taskId);
    pagedHistoryTasks.push(task);
    assert.ok(pagedHistoryIds.length <= expectedHistoryIds.length);
    historyCursor = historyResult.nextCursor;
    if (historyCursor != null) assert.match(historyCursor, /^[A-Za-z0-9_-]{1,256}$/u);
  } while (historyCursor != null);
  assert.deepEqual(pagedHistoryIds, expectedHistoryIds);
  assert.equal(new Set(pagedHistoryIds).size, pagedHistoryIds.length);
  assertError(await callFunction('listRtTaskHistory', {}), 'PERMISSION_DENIED');
  assertError(await callFunction('listRtTaskHistory', {}, resident.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('listRtTaskHistory', {}, noMembership.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('listRtTaskHistory', {}, inactive.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('listRtTaskHistory', {}, invalidRole.idToken), 'PERMISSION_DENIED');
  assert.equal(pagedHistoryTasks.filter((task) => task.status === 'CANCELLED').length, 1);
  const cancelledHistoryTask = pagedHistoryTasks.find((task) => task.status === 'CANCELLED');
  assert.ok(cancelledHistoryTask.cancelledAt);
  assert.ok(pagedHistoryTasks.filter((task) => task.status === 'ACTIVE')
    .every((task) => task.cancelledAt === null && task.closedAt === null));
  const historyForOperatorB = await callFunction('listRtTaskHistory', {}, operatorB.idToken);
  assert.equal(historyForOperatorB.status, 200, JSON.stringify(historyForOperatorB.body));
  assert.deepEqual(historyForOperatorB.body.result.tasks.map((task) => task.taskId), [foreignTaskId]);
  for (const malformedInput of [
    { pageSize: 0 },
    { pageSize: 51 },
    { rtId: 'rt-task-a' },
    { actorUid: operatorA.localId },
  ]) {
    assertError(await callFunction('listRtTaskHistory', malformedInput, operatorA.idToken),
      'INVALID_ARGUMENT');
  }

  const recapBeforeReplacement = await callFunction('getTaskResponseRecap', {
    taskId: draft.campaignId,
  }, operatorA.idToken);
  assert.equal(recapBeforeReplacement.status, 200, JSON.stringify(recapBeforeReplacement.body));
  assert.equal(recapBeforeReplacement.body.result.taskId, draft.campaignId);
  assert.equal(recapBeforeReplacement.body.result.recordedResponseCount, 1);
  assert.equal(recapBeforeReplacement.body.result.verifiedCompleteCount, 1);
  const auditId = `${draft.campaignId}_activated`;
  const audit = await readDocument('task_audit_events', auditId);
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.rtId.stringValue, 'rt-task-a');
  assert.equal(audit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(audit.body.fields.action.stringValue, 'CAMPAIGN_ACTIVATED');
  assert.equal(audit.body.fields.campaignId.stringValue, draft.campaignId);
  assert.equal(audit.body.fields.commandHash.stringValue, crypto.createHash('sha256')
    .update(commandId).digest('hex'));
  assert.equal(Object.keys(audit.body.fields).some((key) =>
    ['nickname', 'fullAddress', 'latitude', 'longitude', 'nik'].includes(key)), false);

  await seedTemplate({
    templateId: 'safe_household_prep',
    title: 'Changed after activation',
    coreInstruction: 'Changed content after activation.',
    safetyInstruction: 'Changed safety text after activation.',
  });
  const historicalSnapshot = await readDocument('task_campaigns', draft.campaignId);
  const historicalTemplate = historicalSnapshot.body.fields.templateSnapshot.mapValue.fields;
  assert.equal(historicalTemplate.title.stringValue, 'Persiapan rumah tangga');
  assert.equal(
    historicalTemplate.safetyInstruction.stringValue,
    'Jangan mendekati air banjir atau instalasi listrik yang basah.',
  );

  const secondDraft = await callFunction('createTaskDraft', {
    ...draftPayload,
    templateId: 'template_mutable',
    requestId: randomRequestId(),
  }, operatorA.idToken);
  assert.equal(secondDraft.status, 200, JSON.stringify(secondDraft.body));
  await seedTemplate({
    templateId: 'template_mutable',
    title: 'Changed without a version increment',
  });
  const changedTemplateActivation = await callFunction('activateTaskCampaign', {
    campaignId: secondDraft.body.result.campaignId,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assertError(changedTemplateActivation, 'FAILED_PRECONDITION');

  await seedOperator(replacementOperator.localId, { rtId: 'rt-task-a' });
  await seedOperator(operatorA.localId, { rtId: 'rt-task-a', active: false });
  assertError(await callFunction('listRtTaskHistory', {}, operatorA.idToken), 'PERMISSION_DENIED');
  const replacementHistory = await callFunction(
    'listRtTaskHistory', {}, replacementOperator.idToken,
  );
  assert.equal(replacementHistory.status, 200, JSON.stringify(replacementHistory.body));
  assert.deepEqual(replacementHistory.body.result.tasks.map((task) => task.taskId),
    expectedHistoryIds);
  assert.equal(replacementHistory.body.result.nextCursor, null);
  const replacementRecap = await callFunction('getTaskResponseRecap', {
    taskId: draft.campaignId,
  }, replacementOperator.idToken);
  assert.equal(replacementRecap.status, 200, JSON.stringify(replacementRecap.body));
  assert.equal(replacementRecap.body.result.taskTitle, 'Persiapan rumah tangga');
  assert.equal(replacementRecap.body.result.recordedResponseCount, 1);
  assert.equal(replacementRecap.body.result.verifiedCompleteCount, 1);
  const retainedActivationAudit = await readDocument('task_audit_events', auditId);
  assert.equal(retainedActivationAudit.status, 200, JSON.stringify(retainedActivationAudit.body));
  assert.equal(retainedActivationAudit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(retainedActivationAudit.body.fields.action.stringValue, 'CAMPAIGN_ACTIVATED');
  const retainedCancellationAudit = await readDocument(
    'task_audit_events', `${draft.campaignId}_cancelled`,
  );
  assert.equal(retainedCancellationAudit.status, 200, JSON.stringify(retainedCancellationAudit.body));
  assert.equal(retainedCancellationAudit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(retainedCancellationAudit.body.fields.action.stringValue, 'CAMPAIGN_CANCELLED');
  const retainedVerificationAudit = await readDocument(
    'task_audit_events', `${historyResponseId}_verified`,
  );
  assert.equal(retainedVerificationAudit.status, 200, JSON.stringify(retainedVerificationAudit.body));
  assert.equal(retainedVerificationAudit.body.fields.rtId.stringValue, 'rt-task-a');
  assert.equal(retainedVerificationAudit.body.fields.actorUid.stringValue, operatorA.localId);
  assert.equal(retainedVerificationAudit.body.fields.action.stringValue,
    'TASK_COMPLETION_VERIFIED');

  const malformedTaskId = 'f'.repeat(40);
  await seedDocument('task_campaigns', malformedTaskId, {
    campaignId: malformedTaskId,
    rtId: 'rt-task-a',
    status: 'ACTIVE',
    activatedAt: sharedActivatedAt,
    deadline: new Date('2026-10-06T00:00:00.000Z'),
  });
  assertError(await callFunction('listRtTaskHistory', {}, replacementOperator.idToken),
    'FAILED_PRECONDITION');
  const malformedDelete = await request('DELETE', documentUrl('task_campaigns', malformedTaskId), {
    token: 'owner',
  });
  assert.equal(malformedDelete.status, 200, JSON.stringify(malformedDelete.body));

  for (const collection of ['task_templates', 'task_campaigns', 'task_audit_events']) {
    const directRead = await request('GET', documentUrl(collection, draft.campaignId), {
      token: operatorA.idToken,
    });
    assert.equal(directRead.status, 403, `${collection} direct read was allowed`);
    const directWrite = await request('PATCH', documentUrl(collection, `client-${collection}`), {
      token: operatorA.idToken,
      body: { fields: { status: { stringValue: 'ACTIVE' } } },
    });
    assert.equal(directWrite.status, 403, `${collection} direct write was allowed`);
  }
});

test('explicit closure is same-RT, idempotent, excluded from residents, and exposes safe timeline events', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-close-${suffix}`;
  const operator = await createAccount();
  const foreignOperator = await createAccount();
  const replacementOperator = await createAccount();
  const resident = await createAccount({ anonymous: true });
  await seedOperator(operator.localId, { rtId });
  await seedOperator(foreignOperator.localId, { rtId: `rt-other-${suffix}` });
  await seedOperator(replacementOperator.localId, { rtId });
  const templateId = `close_safe_${suffix.slice(0, 8)}`;
  await seedTemplate({ templateId });

  const joinCode = `JC${crypto.randomBytes(8).toString('hex').toUpperCase()}`;
  await seedCommunity(rtId, joinCode);
  const session = await callFunction('createResidentSession', {
    joinCode,
    nickname: 'Warga Uji',
    requestId: randomRequestId(),
  });
  assert.equal(session.status, 200, JSON.stringify(session.body));
  const queuedResident = await callFunction('createResidentSession', {
    joinCode,
    nickname: 'Warga Offline',
    requestId: randomRequestId(),
  });
  assert.equal(queuedResident.status, 200, JSON.stringify(queuedResident.body));

  const draft = await callFunction('createTaskDraft', {
    templateId,
    version: 1,
    deadline: DEADLINE,
    locationReference: 'COMMUNITY_GENERAL_AREA',
    requestId: randomRequestId(),
  }, operator.idToken);
  assert.equal(draft.status, 200, JSON.stringify(draft.body));
  const taskId = draft.body.result.campaignId;
  const activationCommandId = randomRequestId();
  const activation = await callFunction('activateTaskCampaign', {
    campaignId: taskId,
    commandId: activationCommandId,
  }, operator.idToken);
  assert.equal(activation.status, 200, JSON.stringify(activation.body));

  const residentBeforeClose = await callFunction('listResidentActiveTasks', {
    sessionToken: session.body.result.sessionToken,
  });
  assert.deepEqual(residentBeforeClose.body.result.items.map((item) => item.taskId), [taskId]);
  const residentJoin = await callFunction('recordResidentTaskResponse', {
    sessionToken: session.body.result.sessionToken,
    taskId,
    choice: 'JOINED',
    commandId: randomRequestId(),
  });
  assert.equal(residentJoin.status, 200, JSON.stringify(residentJoin.body));
  assertError(await callFunction('closeTaskCampaign', {
    taskId,
    commandId: randomRequestId(),
  }, foreignOperator.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('closeTaskCampaign', {
    taskId,
    commandId: randomRequestId(),
    rtId,
  }, operator.idToken), 'INVALID_ARGUMENT');
  assertError(await callFunction('closeTaskCampaign', {
    taskId,
    commandId: randomRequestId(),
  }, resident.idToken), 'PERMISSION_DENIED');

  const closePayload = { taskId, commandId: randomRequestId() };
  const closeResults = await Promise.all([
    callFunction('closeTaskCampaign', closePayload, operator.idToken),
    callFunction('closeTaskCampaign', closePayload, operator.idToken),
  ]);
  for (const result of closeResults) {
    assert.equal(result.status, 200, JSON.stringify(result.body));
    assert.deepEqual(result.body.result, { taskId, status: 'CLOSED' });
  }
  const closeReplay = await callFunction('closeTaskCampaign', closePayload, operator.idToken);
  assert.equal(closeReplay.status, 200, JSON.stringify(closeReplay.body));
  assertError(await callFunction('closeTaskCampaign', {
    taskId,
    commandId: randomRequestId(),
  }, operator.idToken), 'FAILED_PRECONDITION');

  const stored = await readDocument('task_campaigns', taskId);
  assert.equal(stored.status, 200, JSON.stringify(stored.body));
  assert.equal(stored.body.fields.status.stringValue, 'CLOSED');
  assert.equal(stored.body.fields.closedByOperatorUid.stringValue, operator.localId);
  assert.match(stored.body.fields.closureCommandHash.stringValue, /^[a-f0-9]{64}$/u);
  assert.ok(stored.body.fields.closedAt.timestampValue);
  assert.equal(stored.body.fields.commandId, undefined);

  const closeAuditId = `${taskId}_closed`;
  const closeAudit = await readDocument('task_audit_events', closeAuditId);
  assert.equal(closeAudit.status, 200, JSON.stringify(closeAudit.body));
  assert.equal(closeAudit.body.fields.action.stringValue, 'CAMPAIGN_CLOSED');
  assert.equal(closeAudit.body.fields.occurredAt.timestampValue,
    stored.body.fields.closedAt.timestampValue);
  assert.equal(closeAudit.body.fields.actorUid.stringValue, operator.localId);
  assert.equal(closeAudit.body.fields.commandHash.stringValue,
    crypto.createHash('sha256').update(closePayload.commandId).digest('hex'));
  assert.equal(closeAudit.body.fields.commandId, undefined);
  const audits = await request('GET', `${FIRESTORE_BASE}/task_audit_events?pageSize=100`, {
    token: 'owner',
  });
  assert.equal(audits.status, 200, JSON.stringify(audits.body));
  assert.equal((audits.body.documents ?? []).filter((document) =>
    document.name.endsWith(`/${closeAuditId}`)).length, 1);

  const operatorActive = await callFunction('listActiveTaskCampaigns', {}, operator.idToken);
  assert.deepEqual(operatorActive.body.result.tasks, []);
  const residentAfterClose = await callFunction('listResidentActiveTasks', {
    sessionToken: session.body.result.sessionToken,
  });
  assert.deepEqual(residentAfterClose.body.result.items, []);
  const queuedResponseReplay = await callFunction('recordResidentTaskResponse', {
    sessionToken: queuedResident.body.result.sessionToken,
    taskId,
    choice: 'JOINED',
    commandId: randomRequestId(),
  });
  assertError(queuedResponseReplay, 'PERMISSION_DENIED');
  const queuedCompletionReplay = await callFunction('submitTaskCompletion', {
    sessionToken: session.body.result.sessionToken,
    taskId,
    note: null,
    commandId: randomRequestId(),
  });
  assertError(queuedCompletionReplay, 'PERMISSION_DENIED');

  const history = await callFunction('listRtTaskHistory', { pageSize: 1 }, operator.idToken);
  assert.equal(history.status, 200, JSON.stringify(history.body));
  assert.equal(history.body.result.tasks.length, 1);
  assert.equal(history.body.result.tasks[0].taskId, taskId);
  assert.equal(history.body.result.tasks[0].status, 'CLOSED');
  assert.equal(history.body.result.tasks[0].cancelledAt, null);
  assert.ok(history.body.result.tasks[0].closedAt);

  const events = await callFunction('listTaskLifecycleEvents', { taskId }, operator.idToken);
  assert.equal(events.status, 200, JSON.stringify(events.body));
  assert.deepEqual(events.body.result.events.map((event) => event.eventType), [
    'ACTIVATED', 'CLOSED',
  ]);
  assert.deepEqual(Object.keys(events.body.result.events[0]).sort(), [
    'eventType', 'occurredAt',
  ]);
  assert.equal(JSON.stringify(events.body.result).includes(operator.localId), false);
  assert.equal(JSON.stringify(events.body.result).includes('commandHash'), false);
  assertError(await callFunction('listTaskLifecycleEvents', {
    taskId,
    rtId,
  }, operator.idToken), 'INVALID_ARGUMENT');
  assertError(await callFunction('listTaskLifecycleEvents', { taskId }, foreignOperator.idToken),
    'PERMISSION_DENIED');
  assertError(await callFunction('listTaskLifecycleEvents', { taskId }, resident.idToken),
    'PERMISSION_DENIED');
  const replacementEvents = await callFunction(
    'listTaskLifecycleEvents', { taskId }, replacementOperator.idToken,
  );
  assert.equal(replacementEvents.status, 200, JSON.stringify(replacementEvents.body));
  assert.deepEqual(replacementEvents.body.result.events.map((event) => event.eventType), [
    'ACTIVATED', 'CLOSED',
  ]);

  const directAuditRead = await request('GET', documentUrl('task_audit_events', closeAuditId), {
    token: operator.idToken,
  });
  assert.notEqual(directAuditRead.status, 200,
    'lifecycle audit records must remain callable-only');
  await updateDocumentFields('task_audit_events', closeAuditId, {
    action: 'CORRUPTED',
  });
  const inconsistentEvents = await callFunction(
    'listTaskLifecycleEvents', { taskId }, operator.idToken,
  );
  assertError(inconsistentEvents, 'FAILED_PRECONDITION');
});
