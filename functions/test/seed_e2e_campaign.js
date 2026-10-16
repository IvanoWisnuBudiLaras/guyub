// Seeds everything an end-to-end AT-006 run needs, through the real callables
// on the Functions emulator (not by writing Firestore directly), so the seeded
// state is one the system could actually have produced.
//
//   node functions/test/seed_e2e_campaign.js
//
// Prints the join code and the campaign id the e2e test expects.

const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, firestore: 8080, functions: 5001 };
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const FUNCTIONS_BASE = `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}`;
const FIRESTORE_BASE =
  `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const RT = 'rt-e2e';
const JOIN_CODE = 'GUYUBE2E2026';
// Fixed so the e2e suite can sign in as an operator. Emulator-only throwaway
// account; it never exists in a real project.
const OPERATOR_EMAIL = 'operator@guyub.test';
const OPERATOR_PASSWORD = 'test-password-123';
const TEMPLATE_ID = 'safe_household_prep';
const TEMPLATE_VERSION = 1;

// Fixed so the e2e test can assert on the exact locked strings.
const CORE_INSTRUCTION = 'Simpan dokumen penting di wadah yang mudah dijangkau.';
const SAFETY_INSTRUCTION = 'Jangan mendekati air banjir atau instalasi listrik basah.';
const TASK_TITLE = 'Persiapan rumah tangga';

function randomId() {
  return crypto.randomBytes(32).toString('base64url');
}

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

async function seed(collection, id, fields) {
  const response = await request('PATCH', `${FIRESTORE_BASE}/${collection}/${id}`, {
    token: 'owner',
    body: { fields },
  });
  if (response.status !== 200) {
    throw new Error(`seed ${collection}/${id}: ${response.status} ${JSON.stringify(response.body)}`);
  }
}

async function call(name, data, idToken) {
  const response = await request('POST', `${FUNCTIONS_BASE}/${name}`, {
    token: idToken,
    body: { data },
  });
  return response;
}

function requireOk(label, response) {
  if (response.status !== 200) {
    throw new Error(`${label} failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.result;
}

async function main() {
  // 1. The RT and its join code.
  await seed('rt_communities', RT, {
    displayName: { stringValue: `Komunitas ${RT}` },
    rtLabel: { stringValue: 'RT E2E' },
    joinCodeHash: { stringValue: hashJoinCode(JOIN_CODE) },
    joinCodeActive: { booleanValue: true },
  });

  // 2. A reviewed, enabled safe template — the only kind activation accepts.
  await seed('task_templates', `${TEMPLATE_ID}_v${TEMPLATE_VERSION}`, {
    templateId: { stringValue: TEMPLATE_ID },
    version: { integerValue: String(TEMPLATE_VERSION) },
    title: { stringValue: TASK_TITLE },
    category: { stringValue: 'HOUSEHOLD_PREPARATION' },
    coreInstruction: { stringValue: CORE_INSTRUCTION },
    safetyInstruction: { stringValue: SAFETY_INSTRUCTION },
    estimatedDurationMinutes: { integerValue: '30' },
    enabled: { booleanValue: true },
    reviewStatus: { stringValue: 'approved' },
    reviewedBy: { stringValue: 'trusted-reviewer' },
    reviewedAt: { timestampValue: new Date().toISOString() },
  });

  // 3. An operator with an active membership in that RT.
  // Reuse the account if the suite is run twice against one emulator.
  let account = await request('POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, {
    body: {
      returnSecureToken: true,
      email: OPERATOR_EMAIL,
      password: OPERATOR_PASSWORD,
    },
  });
  if (account.status !== 200) {
    account = await request('POST', `${AUTH_BASE}/accounts:signInWithPassword?key=fake-api-key`, {
      body: { returnSecureToken: true, email: OPERATOR_EMAIL, password: OPERATOR_PASSWORD },
    });
  }
  if (account.status !== 200) {
    throw new Error(`operator account: ${account.status} ${JSON.stringify(account.body)}`);
  }
  // displayName is required: FirebaseOperatorAuthBoundary returns null without
  // it, so sign-in would fail even with correct credentials.
  await seed('operators', account.body.localId, {
    active: { booleanValue: true },
    role: { stringValue: 'KETUA_RT_RW' },
    rtId: { stringValue: RT },
    displayName: { stringValue: 'Ketua RT E2E' },
  });

  // 4. Draft and activate through the real callables, so the campaign carries a
  //    genuine immutable template snapshot rather than hand-written fields.
  const deadline = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const draft = requireOk('createTaskDraft', await call('createTaskDraft', {
    templateId: TEMPLATE_ID,
    version: TEMPLATE_VERSION,
    deadline,
    locationReference: 'COMMUNITY_GENERAL_AREA',
    requestId: randomId(),
  }, account.body.idToken));

  const activation = requireOk('activateTaskCampaign', await call('activateTaskCampaign', {
    campaignId: draft.campaignId,
    commandId: randomId(),
  }, account.body.idToken));

  if (activation.status !== 'ACTIVE') {
    throw new Error(`campaign not ACTIVE: ${JSON.stringify(activation)}`);
  }

  console.log(JSON.stringify({
    rt: RT,
    joinCode: JOIN_CODE,
    operatorEmail: OPERATOR_EMAIL,
    operatorPassword: OPERATOR_PASSWORD,
    campaignId: draft.campaignId,
    title: TASK_TITLE,
    safetyInstruction: SAFETY_INSTRUCTION,
    coreInstruction: CORE_INSTRUCTION,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
