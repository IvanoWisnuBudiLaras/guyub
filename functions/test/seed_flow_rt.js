// Seeds the RT community the Dart contract test enrolls against, plus the
// reviewed safe template it needs. Uses the emulator's `owner` bypass because
// Firestore rules deny all client writes.
//
//   node functions/test/seed_flow_rt.js

const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = process.env.GCLOUD_PROJECT ?? 'demo-guyub-functions';
const FIRESTORE_BASE =
  `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const RT = 'rt-flow';
const JOIN_CODE = 'KODEFLOW1234';
const TEMPLATE_ID = 'safe_household_prep';

async function patch(collection, id, fields) {
  const response = await fetch(`${FIRESTORE_BASE}/${collection}/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ fields }),
  });
  if (response.status !== 200) {
    throw new Error(`seed ${collection}/${id} failed: ${response.status} ${await response.text()}`);
  }
}

async function main() {
  await patch('rt_communities', RT, {
    displayName: { stringValue: `Komunitas ${RT}` },
    rtLabel: { stringValue: 'RT Alur' },
    joinCodeHash: { stringValue: hashJoinCode(JOIN_CODE) },
    joinCodeActive: { booleanValue: true },
  });

  await patch('task_templates', `${TEMPLATE_ID}_v1`, {
    templateId: { stringValue: TEMPLATE_ID },
    version: { integerValue: '1' },
    title: { stringValue: 'Persiapan rumah tangga' },
    category: { stringValue: 'HOUSEHOLD_PREPARATION' },
    coreInstruction: { stringValue: 'Simpan dokumen penting di wadah yang mudah dijangkau.' },
    safetyInstruction: { stringValue: 'Jangan mendekati air banjir atau instalasi listrik basah.' },
    estimatedDurationMinutes: { integerValue: '30' },
    enabled: { booleanValue: true },
    reviewStatus: { stringValue: 'approved' },
    reviewedBy: { stringValue: 'trusted-reviewer' },
    reviewedAt: { timestampValue: new Date().toISOString() },
  });

  console.log(`seeded ${RT} with join code ${JOIN_CODE}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
