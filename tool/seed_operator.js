/**
 * Seed: buat akun operator RT di emulator Auth + Firestore
 * untuk wilayah Kabupaten Tulungagung, Jawa Timur.
 *
 * Jalankan setelah emulator aktif:
 *   node tool/seed_operator.js
 *
 * Kredensial:
 *   Email   : ketua.rt01@guyub.id
 *   Password: Password123
 */

'use strict';

const crypto = require('node:crypto');

const PROJECT_ID = 'demo-guyub-development';
const AUTH_HOST = '127.0.0.1:9099';
const FIRESTORE_HOST = '127.0.0.1:8080';

const OPERATOR_EMAIL = 'ketua.rt01@guyub.id';
const OPERATOR_PASSWORD = 'Password123';
const OPERATOR_DISPLAY_NAME = 'Ketua RT 01 Kedungwaru';
const RT_ID = 'rt-01-demo';
const RT_LABEL = 'RT 01 / RW 02 Kedungwaru';
const RT_JOIN_CODE = 'GUYUBRT01DEMO';

function hashJoinCode(code) {
  return crypto.createHash('sha256').update(code.trim().toUpperCase(), 'utf8').digest('hex');
}

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') {
    if (Number.isInteger(val)) return { integerValue: String(val) };
    return { doubleValue: val };
  }
  if (typeof val === 'string') return { stringValue: val };
  if (val instanceof Date) return { timestampValue: val.toISOString() };
  if (Array.isArray(val)) {
    return { arrayValue: { values: val.map(toFirestoreValue) } };
  }
  if (typeof val === 'object') {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  throw new Error(`Tipe data tidak didukung: ${typeof val}`);
}

async function seedFirestoreDoc(path, data) {
  const url = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/${path}`;
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    fields[k] = toFirestoreValue(v);
  }

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: 'Bearer owner',
    },
    body: JSON.stringify({ fields }),
  });

  const resJson = await res.json();
  if (!res.ok) {
    throw new Error(`Gagal seed ${path}: ${JSON.stringify(resJson)}`);
  }
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
  await seedFirestoreDoc(`operators/${uid}`, {
    active: true,
    role: 'KETUA_RT_RW',
    rtId: RT_ID,
    displayName: OPERATOR_DISPLAY_NAME,
  });
  console.log(`Firestore operators/${uid} berhasil diseed.`);
}

async function seedFirestoreCommunity() {
  await seedFirestoreDoc(`rt_communities/${RT_ID}`, {
    displayName: `Demo ${RT_LABEL}`,
    rtLabel: RT_LABEL,
    joinCodeHash: hashJoinCode(RT_JOIN_CODE),
    joinCodeActive: true,
  });
  console.log(`Firestore rt_communities/${RT_ID} berhasil diseed (Join Code: ${RT_JOIN_CODE}).`);
}

async function seedProxyResidents() {
  const now = new Date();
  const proxy1 = crypto.createHash('sha256').update('resident-proxy-mbah-supardi-demo').digest('hex').slice(0, 40);
  const proxy2 = crypto.createHash('sha256').update('resident-proxy-ibu-aminah-demo').digest('hex').slice(0, 40);

  await seedFirestoreDoc(`resident_profiles/${proxy1}`, {
    residentId: proxy1,
    rtId: RT_ID,
    nickname: 'Mbah Supardi (DEMO)',
    houseNumber: '12',
    needsAssistance: true,
    createdBy: 'proxy',
    createdAt: now,
  });

  await seedFirestoreDoc(`resident_profiles/${proxy2}`, {
    residentId: proxy2,
    rtId: RT_ID,
    nickname: 'Ibu Aminah (DEMO)',
    houseNumber: '05A',
    needsAssistance: true,
    createdBy: 'proxy',
    createdAt: now,
  });

  console.log(`Firestore resident_profiles (2 data warga rentan DEMO) berhasil diseed.`);
}

async function seedWeather() {
  const now = new Date();
  const weatherSource = {
    rtId: RT_ID,
    source: 'BMKG',
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'Admin Wilayah Tulungagung',
    reviewedAt: now,
    endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=35.04.03.2010',
    maximumAgeSeconds: 86400,
    normalization: {
      rainfallMmPath: ['data', 0, 'forecast', 'rainfall_mm'],
      sourceUpdatedAtPath: ['data', 0, 'forecast', 'source_updated_at'],
    },
  };
  const sourceFingerprint = crypto.createHash('sha256').update(JSON.stringify([
    weatherSource.rtId,
    weatherSource.endpoint,
    weatherSource.maximumAgeSeconds,
    weatherSource.normalization.rainfallMmPath,
    weatherSource.normalization.sourceUpdatedAtPath,
  ]), 'utf8').digest('hex');

  await seedFirestoreDoc(`weather_sources/${RT_ID}`, {
    ...weatherSource,
    sourceFingerprint,
  });

  const rainfallMm = 14.5;
  const snapshotId = crypto.createHash('sha256').update(JSON.stringify([
    RT_ID,
    sourceFingerprint,
    now.toISOString(),
    rainfallMm,
  ]), 'utf8').digest('hex').slice(0, 40);

  await seedFirestoreDoc(`weather_snapshots/${snapshotId}`, {
    snapshotId,
    rtId: RT_ID,
    source: 'BMKG',
    sourceFingerprint,
    sourceUpdatedAt: now,
    fetchedAt: now,
    rainfallMm,
    isLastValid: true,
  });
  await seedFirestoreDoc(`weather_last_valid_snapshots/${RT_ID}`, {
    rtId: RT_ID,
    snapshotId,
    sourceFingerprint,
    sourceUpdatedAt: now,
    fetchedAt: now,
    rainfallMm,
  });
  console.log(`Firestore weather_snapshots (${snapshotId}) berhasil diseed.`);

  try {
    const legacyWeatherUrl = `http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/(default)/documents/weather_snapshots/snapshot-${RT_ID}-demo`;
    await fetch(legacyWeatherUrl, { method: 'DELETE', headers: { Authorization: 'Bearer owner' } });
  } catch (_) {}
}

async function main() {
  console.log('=== Seeder Operator RT Tulungagung (emulator) ===');
  const uid = await createAuthUser();
  await seedFirestoreOperator(uid);
  await seedFirestoreCommunity();
  await seedProxyResidents();
  await seedWeather();
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
