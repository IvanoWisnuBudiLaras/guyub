// End-to-end system flow through the HTTP adapter: the same journey the app
// takes, but with Cloud Functions replaced by server/http_adapter.js.
//
// Operator drafts -> activates -> resident enrolls -> sees the task -> joins ->
// completes -> operator verifies. If any link in the new transport is broken,
// this fails.
//
//   npx firebase-tools emulators:exec --project demo-guyub-functions \
//     --only auth,firestore,storage "node --test functions/test/http_adapter_system_flow.test.js"

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'demo-guyub-functions';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, firestore: 8080 };
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const FIRESTORE_BASE =
  `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const ADAPTER = process.env.GUYUB_ADAPTER_URL ?? 'http://127.0.0.1:8787';

const RT = 'rt-flow';
const JOIN_CODE = 'KODEFLOW1234';
const TEMPLATE_ID = 'safe_household_prep';
const DEADLINE = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();

function randomId() {
  return crypto.randomBytes(32).toString('base64url');
}

async function request(method, url, { token, body, headers: extra } = {}) {
  const headers = { 'Content-Type': 'application/json', ...extra };
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

// The one call shape the adapter serves, mirroring the app's httpsCallable.
async function call(name, data, idToken) {
  return request('POST', `${ADAPTER}/call/${name}`, {
    token: idToken,
    body: { data },
  });
}

function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}

function encodeValue(value) {
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (value instanceof Date) return { timestampValue: value.toISOString() };
  throw new Error(`Unsupported value: ${String(value)}`);
}

async function seed(collection, id, record) {
  const fields = Object.fromEntries(
    Object.entries(record).map(([k, v]) => [k, encodeValue(v)]),
  );
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner',
    body: { fields },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

async function createOperator(email) {
  const result = await request('POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, {
    body: {
      returnSecureToken: true,
      email: email ?? `flow-${crypto.randomUUID()}@example.invalid`,
      password: 'test-password-123',
    },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  await seed('operators', result.body.localId, {
    active: true,
    role: 'KETUA_RT_RW',
    rtId: RT,
  });
  return result.body;
}

test('the full operator -> resident -> verification journey runs through the HTTP adapter', async () => {
  await seed('rt_communities', RT, {
    displayName: `Komunitas ${RT}`,
    rtLabel: 'RT Alur',
    joinCodeHash: hashJoinCode(JOIN_CODE),
    joinCodeActive: true,
  });
  await seed('task_templates', `${TEMPLATE_ID}_v1`, {
    templateId: TEMPLATE_ID,
    version: 1,
    title: 'Persiapan rumah tangga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting di wadah yang mudah dijangkau.',
    safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik basah.',
    estimatedDurationMinutes: 30,
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'trusted-reviewer',
    reviewedAt: new Date(),
  });

  const operator = await createOperator();

  // 1. Operator drafts a task from the reviewed safe catalog.
  const draft = await call('createTaskDraft', {
    templateId: TEMPLATE_ID,
    version: 1,
    deadline: DEADLINE,
    locationReference: 'COMMUNITY_GENERAL_AREA',
    requestId: randomId(),
  }, operator.idToken);
  assert.equal(draft.status, 200, JSON.stringify(draft.body));
  const campaignId = draft.body.data.campaignId;
  assert.ok(typeof campaignId === 'string' && campaignId.length > 0);

  // 2. Operator activates it. Nothing is resident-visible before this step.
  const activation = await call('activateTaskCampaign', {
    campaignId,
    commandId: randomId(),
  }, operator.idToken);
  assert.equal(activation.status, 200, JSON.stringify(activation.body));
  assert.equal(activation.body.data.status, 'ACTIVE');

  // 3. Resident enrolls with the RT join code.
  const enrollment = await call('createResidentSession', {
    joinCode: JOIN_CODE,
    nickname: 'Sari',
    requestId: randomId(),
  });
  assert.equal(enrollment.status, 200, JSON.stringify(enrollment.body));
  const sessionToken = enrollment.body.data.sessionToken;
  assert.ok(typeof sessionToken === 'string' && sessionToken.length >= 32);

  // 4. Resident sees the active task, with the locked safety instruction.
  const active = await call('listResidentActiveTasks', { sessionToken });
  assert.equal(active.status, 200, JSON.stringify(active.body));
  assert.equal(active.body.data.items.length, 1);
  const task = active.body.data.items[0];
  assert.equal(task.taskId, campaignId);
  assert.equal(task.participationState, 'UNRESPONDED');
  assert.equal(task.templateSnapshot.safetyInstruction,
    'Jangan mendekati air banjir atau instalasi listrik basah.');
  assert.equal('residentId' in task, false);

  // 5. Resident joins voluntarily.
  const join = await call('recordResidentTaskResponse', {
    sessionToken,
    taskId: campaignId,
    choice: 'JOINED',
    commandId: randomId(),
  });
  assert.equal(join.status, 200, JSON.stringify(join.body));
  assert.equal(join.body.data.participationState, 'JOINED');

  // 6. Resident submits completion. It stays pending until an operator verifies.
  const completion = await call('submitTaskCompletion', {
    sessionToken,
    taskId: campaignId,
    note: null,
    commandId: randomId(),
  });
  assert.equal(completion.status, 200, JSON.stringify(completion.body));
  assert.equal(completion.body.data.completionState, 'PENDING_RT_VERIFICATION');

  // 7. Operator sees it in the verification queue.
  const pending = await call('listPendingTaskVerifications', {}, operator.idToken);
  assert.equal(pending.status, 200, JSON.stringify(pending.body));
  assert.equal(pending.body.data.items.length, 1);
  const responseId = pending.body.data.items[0].responseId;
  assert.equal(pending.body.data.items[0].nickname, 'Sari');

  // 8. Operator verifies. Only now is the task officially complete.
  const verified = await call('verifyTaskCompletion', {
    responseId,
    commandId: randomId(),
  }, operator.idToken);
  assert.equal(verified.status, 200, JSON.stringify(verified.body));
  assert.equal(verified.body.data.completionState, 'VERIFIED_COMPLETE');

  // 9. The audit trail exists and is written by the server, not the client.
  const audit = await request('GET', documentUrl('task_audit_events', `${responseId}_verified`), {
    token: 'owner',
  });
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.action.stringValue, 'TASK_COMPLETION_VERIFIED');
});

test('a resident cannot verify their own completion through the new transport', async () => {
  // The journey above proved the happy path. This proves the new transport did
  // not open a hole in the one boundary that matters most (S-07).
  const operator = await createOperator();

  const enrollment = await call('createResidentSession', {
    joinCode: JOIN_CODE,
    nickname: 'Budi',
    requestId: randomId(),
  });
  assert.equal(enrollment.status, 200, JSON.stringify(enrollment.body));

  const active = await call('listResidentActiveTasks', {
    sessionToken: enrollment.body.data.sessionToken,
  });
  assert.equal(active.status, 200, JSON.stringify(active.body));
  const campaignId = active.body.data.items[0].taskId;

  await call('recordResidentTaskResponse', {
    sessionToken: enrollment.body.data.sessionToken,
    taskId: campaignId,
    choice: 'JOINED',
    commandId: randomId(),
  });
  const completion = await call('submitTaskCompletion', {
    sessionToken: enrollment.body.data.sessionToken,
    taskId: campaignId,
    note: null,
    commandId: randomId(),
  });
  assert.equal(completion.status, 200, JSON.stringify(completion.body));

  const pending = await call('listPendingTaskVerifications', {}, operator.idToken);
  const responseId = pending.body.data.items
    .find((item) => item.nickname === 'Budi').responseId;

  // The resident has no Firebase Auth token at all — only a session token.
  const selfVerify = await call('verifyTaskCompletion', {
    responseId,
    commandId: randomId(),
  });
  assert.ok(selfVerify.status === 401 || selfVerify.status === 403,
    JSON.stringify(selfVerify.body));
  assert.ok(['permission-denied', 'unauthenticated'].includes(selfVerify.body.error.code),
    JSON.stringify(selfVerify.body));

  // And a session token cannot be smuggled in to act as an operator.
  const smuggled = await call('verifyTaskCompletion', {
    responseId,
    commandId: randomId(),
    sessionToken: enrollment.body.data.sessionToken,
  });
  assert.ok(smuggled.status >= 400, JSON.stringify(smuggled.body));
});

test('a callable outside the allow-list is refused', async () => {
  const result = await call('deleteExpiredTaskEvidence', {});
  assert.equal(result.status, 404, JSON.stringify(result.body));
  assert.equal(result.body.error.code, 'not-found');
});

test('every scheduled task runs when called with the shared secret', async () => {
  // Cloud Scheduler invokes these on Cloud Functions. On the HTTP adapter an
  // external cron calls /tasks/<name>, so each one must actually execute.
  const secret = process.env.GUYUB_TASK_SECRET;
  assert.ok(typeof secret === 'string' && secret.length > 0,
    'GUYUB_TASK_SECRET must be set for this test');

  const names = [
    'deleteExpiredTaskEvidence',
    'syncBmkgWeather',
    'sendTaskReminders',
    'escalateUnrespondedTasks',
    'deliverCampaignTransitionNotifications',
  ];

  for (const name of names) {
    const result = await request('POST', `${ADAPTER}/tasks/${name}`, {
      token: undefined,
      body: {},
      headers: { 'x-guyub-task-secret': secret },
    });
    assert.equal(result.status, 200,
      `${name} failed: ${JSON.stringify(result.body)}`);
    assert.ok(result.body.data !== undefined, `${name} returned no data`);
  }
});
