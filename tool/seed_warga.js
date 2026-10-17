/**
 * Seed: Data komunitas RT, kode RT, direktori darurat, cuaca, dan tugas siaga
 * agar dapat langsung login dan beraktivitas sebagai Warga di emulator Guyub.id.
 *
 * Jalankan setelah emulator aktif:
 *   node tool/seed_warga.js
 *
 * Kredensial Login Warga di Aplikasi:
 *   Peran         : Warga ("Saya Warga")
 *   Kode RT       : GUYUBRT01DEMO
 *   Nama Panggilan: Budi (atau nama panggilan Anda bebas)
 */

'use strict';

const crypto = require('node:crypto');

const PROJECT_ID = 'demo-guyub-development';
const FIRESTORE_HOST = '127.0.0.1:8080';
const FUNCTIONS_HOST = '127.0.0.1:5001';
const REGION = 'asia-southeast2';

const RT_ID = 'rt-01-demo';
const RT_LABEL = 'RT 01';
const RT_JOIN_CODE = 'GUYUBRT01DEMO'; // 12-32 karakter alfanumerik kapital
const DEMO_NICKNAME = 'Budi';

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

async function testCallableFunction() {
  try {
    const url = `http://${FUNCTIONS_HOST}/${PROJECT_ID}/${REGION}/createResidentSession`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        data: {
          joinCode: RT_JOIN_CODE,
          nickname: DEMO_NICKNAME,
          requestId: crypto.randomBytes(32).toString('base64url'),
        },
      }),
    });
    const json = await res.json();
    if (res.ok && json.result?.sessionToken) {
      console.log('   [✓] Verifikasi Cloud Function createResidentSession: Sukses.');
    } else {
      console.log('   [i] Respons Cloud Function:', json);
    }
  } catch (err) {
    console.log(`   [i] Emulator Functions (port 5001) belum dapat dihubungi: ${err.message}.`);
  }
}

async function main() {
  console.log('=== Seeder Warga RT (emulator) ===\n');

  const now = new Date();
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000);

  // 1. Komunitas RT dengan Kode Gabung (Join Code) Aktif
  console.log('1. Menyiapkan komunitas RT...');
  await seedFirestoreDoc(`rt_communities/${RT_ID}`, {
    displayName: `Demo ${RT_LABEL}`,
    rtLabel: RT_LABEL,
    joinCodeHash: hashJoinCode(RT_JOIN_CODE),
    joinCodeActive: true,
  });
  console.log(`   [✓] rt_communities/${RT_ID} aktif dengan kode: ${RT_JOIN_CODE}`);

  // 2. Direktori Darurat RT (Kontak & Titik Kumpul)
  console.log('2. Menyiapkan direktori darurat RT...');
  await seedFirestoreDoc(`emergency_directories/${RT_ID}`, {
    rtId: RT_ID,
    state: 'ACTIVE',
    version: 1,
    lastVerifiedAt: now,
    emergencyContacts: [
      { label: 'Ketua RT 01', phone: '081234567890' },
      { label: 'Puskesmas Kelurahan', phone: '0215551234' },
      { label: 'Damkar / BPBD (Darurat)', phone: '112' },
    ],
    assemblyPoints: [
      { label: 'Balai Warga RT 01 (Utama)', publicLocation: 'Jl. Guyub Raya No. 1' },
      { label: 'Masjid Al-Ikhlas (Alternatif)', publicLocation: 'Jl. Guyub II No. 12' },
    ],
    officialReportChannels: [
      { label: 'Call Center BPBD DKI', url: 'https://bpbd.jakarta.go.id' },
      { label: 'Aplikasi JAKI', url: 'https://jaki.jakarta.go.id' },
    ],
  });
  console.log(`   [✓] emergency_directories/${RT_ID} berhasil diseed`);

  // 3. Sumber & Snapshot Cuaca BMKG
  console.log('3. Menyiapkan snapshot cuaca BMKG...');
  const snapshotId = `snapshot-${RT_ID}-demo`;
  await seedFirestoreDoc(`weather_sources/${RT_ID}`, {
    rtId: RT_ID,
    adm4Code: '31.71.01.1001',
    enabled: true,
  });
  await seedFirestoreDoc(`weather_snapshots/${snapshotId}`, {
    snapshotId,
    rtId: RT_ID,
    source: 'BMKG',
    sourceFingerprint: 'demo-fingerprint-rt01',
    sourceUpdatedAt: now,
    fetchedAt: now,
    rainfallMm: 14.5,
    isLastValid: true,
  });
  await seedFirestoreDoc(`weather_last_valid_snapshots/${RT_ID}`, {
    rtId: RT_ID,
    snapshotId,
    sourceFingerprint: 'demo-fingerprint-rt01',
    sourceUpdatedAt: now,
    fetchedAt: now,
    rainfallMm: 14.5,
    isLastValid: true,
  });
  console.log(`   [✓] weather_snapshots & weather_last_valid_snapshots berhasil diseed`);

  // 4. Template & Kampanye Tugas Kesiapsiagaan Aktif
  console.log('4. Menyiapkan katalog tugas siaga aktif...');
  const templateId = 'household-prep';
  const templateVersion = 1;
  const templateSnapshot = {
    templateId,
    version: templateVersion,
    title: 'Siapkan Tas Siaga & Dokumen Penting',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen keluarga, surat berharga, dan obat-obatan darurat ke dalam tas siaga tahan air.',
    safetyInstruction: 'Utamakan keselamatan diri. Jangan menyentuh peralatan listrik yang basah atau terendam air.',
    estimatedDurationMinutes: 30,
  };
  await seedFirestoreDoc(`task_templates/${templateId}_v${templateVersion}`, {
    ...templateSnapshot,
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'Admin Wilayah',
    reviewedAt: now,
  });
  await seedFirestoreDoc(`task_campaigns/campaign-demo-rt01`, {
    campaignId: 'campaign-demo-rt01',
    rtId: RT_ID,
    status: 'ACTIVE',
    templateId,
    templateVersion,
    templateSnapshot,
    coarseLocation: 'ALL_HOUSEHOLDS',
    activatedAt: now,
    deadline: tomorrow,
  });
  console.log(`   [✓] task_campaigns/campaign-demo-rt01 (Tugas Aktif) berhasil diseed`);

  // 5. Uji Callable createResidentSession
  console.log('5. Menguji Callable Function sesi warga...');
  await testCallableFunction();

  console.log('\n============================================================');
  console.log('✅ Seed Warga Berhasil!');
  console.log('============================================================');
  console.log('Petunjuk Login sebagai Warga di Aplikasi Guyub.id:');
  console.log('  1. Buka aplikasi Guyub.id (mode dev/emulator)');
  console.log('  2. Di halaman awal, pilih: "Saya Warga"');
  console.log('  3. Masukkan data:');
  console.log(`     • Kode RT       : ${RT_JOIN_CODE}`);
  console.log(`     • Nama Panggilan: ${DEMO_NICKNAME} (atau nama panggilan Anda)`);
  console.log('  4. Tekan tombol: "Masuk"');
  console.log('============================================================\n');
}

main().catch((err) => {
  console.error('\n❌ Seed warga gagal:', err.message);
  process.exit(1);
});
