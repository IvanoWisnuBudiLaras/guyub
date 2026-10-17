/**
 * Seed: buat akun operator RT di emulator Auth + Firestore.
 *
 * Jalankan setelah emulator aktif:
 *   node tool/seed_operator.js
 *
 * Kredensial:
 *   Email   : ketua.rt01@guyub.id
 *   Password: Password123
 */

'use strict';

const PROJECT_ID = 'demo-guyub-development';
const AUTH_HOST = '127.0.0.1:9099';
const FIRESTORE_HOST = '127.0.0.1:8080';

const OPERATOR_EMAIL = 'ketua.rt01@guyub.id';
const OPERATOR_PASSWORD = 'Password123';
const OPERATOR_DISPLAY_NAME = 'Ketua RT 01';
const RT_ID = 'rt-01-demo';
const RT_LABEL = 'RT 01';

const crypto = require('node:crypto');

const RT_JOIN_CODE = 'GUYUBRT01DEMO';

function hashJoinCode(code) {
  return crypto.createHash('sha256').update(code.trim().toUpperCase(), 'utf8').digest('hex');
}

async function createAuthUser() {
  const url = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test`;
  const body = {
    email: OPERATOR_EMAIL,
    password: OPERATOR_PASSWORD,
    displayName: OPERATOR_DISPLAY_NAME,
    returnSecureToken: true,
  };
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok) {
    if (data.error?.message?.includes('EMAIL_EXISTS')) {
      console.log('Akun sudah ada, mencari uid…');
      return lookupAuthUser();
    }
    throw new Error(`Auth create failed: ${JSON.stringify(data)}`);
  }
  console.log(`Auth user dibuat: ${data.localId}`);
  return data.localId;
}

async function lookupAuthUser() {
  const url = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: OPERATOR_EMAIL,
      password: OPERATOR_PASSWORD,
      returnSecureToken: true,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.localId) {
    throw new Error(`Auth login lookup failed: ${JSON.stringify(data)}`);
  }
  const uid = data.localId;
  console.log(`Auth user ditemukan: ${uid}`);
  return uid;
}

async function seedFirestoreOperator(uid) {
  const url =
    `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/operators/${uid}`;
  const body = {
    fields: {
      active:      { booleanValue: true },
      role:        { stringValue: 'KETUA_RT_RW' }, // harus cocok firestore.rules & fromWireValue()
      rtId:        { stringValue: RT_ID },
      displayName: { stringValue: OPERATOR_DISPLAY_NAME },
    },
  };
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer owner',
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Firestore operator seed failed: ${JSON.stringify(data)}`);
  console.log(`Firestore operators/${uid} berhasil diseed.`);
}

async function seedFirestoreCommunity() {
  const url =
    `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/rt_communities/${RT_ID}`;
  const body = {
    fields: {
      displayName:    { stringValue: `Demo ${RT_LABEL}` },
      rtLabel:        { stringValue: RT_LABEL },
      joinCodeHash:   { stringValue: hashJoinCode(RT_JOIN_CODE) },
      joinCodeActive: { booleanValue: true },
    },
  };
  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer owner',
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(`Firestore community seed failed: ${JSON.stringify(data)}`);
  console.log(`Firestore rt_communities/${RT_ID} berhasil diseed (Join Code: ${RT_JOIN_CODE}).`);
}

async function main() {
  console.log('=== Seeder Operator RT (emulator) ===');
  const uid = await createAuthUser();
  await seedFirestoreOperator(uid);
  await seedFirestoreCommunity();
  console.log('\n✅ Selesai!');
  console.log(`   Operator RT:`);
  console.log(`   Email   : ${OPERATOR_EMAIL}`);
  console.log(`   Password: ${OPERATOR_PASSWORD}`);
  console.log(`\n   Warga (Login di aplikasi dengan):`);
  console.log(`   Kode RT : ${RT_JOIN_CODE}`);
}

main().catch((err) => {
  console.error('❌ Seed gagal:', err.message);
  process.exit(1);
});
