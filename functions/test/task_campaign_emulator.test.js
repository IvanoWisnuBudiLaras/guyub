const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

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
