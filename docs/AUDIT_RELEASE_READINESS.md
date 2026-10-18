# Audit Kesiapan Rilis Produksi Guyub.id (Release Readiness Audit)

> **Tanggal Audit:** 17 Oktober 2026  
> **Status Kelayakan:** ⚠️ **BELUM SIAP RILIS KE MASYARAKAT (Not Ready for Public Production)**  
> **Hasil Pengujian Otomatis:** 284/284 Flutter Unit & Smoke Tests Lulus (100%), 104/104 Cloud Functions Unit Tests Lulus (100%), E2E TypeScript Types Clean (0 Errors).

---

## 1. Ringkasan Eksekutif

Audit ini mengevaluasi kesiapan teknis, arsitektur, UI/UX, keamanan data, dan konfigurasi build Android APK untuk menentukan apakah Guyub.id sudah layak dirilis ke masyarakat umum.

**Kesimpulan:**  
Kualitas kode, domain logic, kepatuhan batas keamanan (*security boundaries*), dan penanganan mode luring (*offline*) sudah **sangat matang**. Namun, aplikasi **belum bisa langsung digunakan masyarakat** karena terdapat **Critical Blockers** pada konfigurasi runtime APK dan infrastruktur deployment backend produksi.

---

## 2. Critical Blockers (Wajib Diselesaikan Sebelum Distribusi APK)

### 🔴 Blocker 1: APK Default Mengarah ke Host Emulator (`10.0.2.2`)
* **Lokasi:** `lib/main.dart` & `lib/app/bootstrap.dart`
* **Masalah:** Nilai default parameter environment di `lib/main.dart` adalah `development`:
  ```dart
  const envRaw = String.fromEnvironment('ENV', defaultValue: 'development');
  ```
  Di mode `development`, `bootstrap.dart` menyalakan flag `useEmulator = true` yang secara otomatis mengarahkan koneksi Auth, Firestore, dan Functions ke emulator lokal host `10.0.2.2`.
* **Dampak:** Jika APK dirilis tanpa flag `--dart-define=ENV=production` atau tanpa entry point `lib/main_prod.dart`, aplikasi di ponsel masyarakat akan mencoba menghubungi `10.0.2.2` (yang tidak ada pada ponsel fisik) sehingga seluruh fitur langsung macet (*fail-closed*).
* **Solusi Wajib:** 
  - Pastikan pipeline CI/CD atau perintah build rilis menggunakan `--target=lib/main_prod.dart` atau menyertakan `--dart-define=ENV=production`.
  - Perbarui skrip workflow `.github/workflows/release-apk.yml`.

### 🔴 Blocker 2: Izin Internet Belum Eksplisit di AndroidManifest Rilis
* **Lokasi:** `android/app/src/main/AndroidManifest.xml`
* **Masalah:** Tag `<uses-permission android:name="android.permission.INTERNET"/>` saat ini hanya berada di `android/app/src/debug/AndroidManifest.xml` dan belum tercantum di `src/main/AndroidManifest.xml`.
* **Dampak:** Pada rilis produksi, manifes debug tidak digabungkan. APK berisiko tidak memiliki izin akses jaringan di sistem operasi Android.
* **Solusi Wajib:** Tambahkan deklarasi izin `INTERNET` secara eksplisit ke dalam `android/app/src/main/AndroidManifest.xml`.

### 🔴 Blocker 3: Backend Cloud Functions & Database Belum Dideploy ke Cloud
* **Lokasi:** `functions/`, `firestore.rules`, `storage.rules`
* **Masalah:** Seluruh Cloud Functions dan aturan keamanan baru berjalan serta diuji di Firebase Emulator lokal (`demo-guyub-functions`). Belum dideploy ke project produksi Google Cloud / Firebase di region `asia-southeast2`.
* **Dampak:** Belum ada endpoint backend hidup di internet. Sesi warga, pembuatan tugas, dan verifikasi tidak dapat merespons permintaan di luar emulator lokal.
* **Solusi Wajib:**
  - Siapkan project Firebase resmi.
  - Jalankan `firebase deploy --only functions,firestore:rules,storage:rules`.
  - Buat bucket Google Cloud Storage untuk bukti foto (`GUYUB_EVIDENCE_BUCKET`) beserta Cloud Scheduler pembersihan 30 hari.

### 🔴 Blocker 4: Penegakan Firebase App Check (Play Integrity)
* **Lokasi:** `lib/app/bootstrap.dart` & `functions/src/callable_options.js`
* **Masalah:** Pada build rilis (`kDebugMode == false`), aplikasi mengaktifkan `AndroidPlayIntegrityProvider()`, dan Cloud Functions memberlakukan `enforceAppCheck: true`.
* **Dampak:** Jika sertifikat penandatanganan APK rilis (SHA-256) belum didaftarkan di Firebase Console App Check dengan Play Integrity, server akan menolak 100% permintaan callable dari ponsel warga.
* **Solusi Wajib:** Daftarkan SHA-256 release keystore ke Firebase Console > App Check > Play Integrity.

### 🔴 Blocker 5: Keystore Penandatanganan Rilis (Release Signing Key)
* **Lokasi:** `android/app/build.gradle.kts` & `android/key.properties`
* **Masalah:** Berkas `key.properties` dan keystore rilis (`guyub-release.jks`) belum dikonfigurasi. Saat ini build rilis masih otomatis menggunakan Android Debug Keystore.
* **Dampak:** APK dengan debug key akan memicu peringatan keamanan mencolok (*Play Protect / Untrusted Source warning*) dan rentan pemalsuan update.
* **Solusi Wajib:** Generate keystore rilis resmi dan simpan kredensialnya di `android/key.properties` serta GitHub Secrets.

---

## 3. Catatan Penyempurnaan UI/UX & Aset

1. **Ikon Aplikasi Android (Launcher Icon)**:
   - Folder `android/app/src/main/res/mipmap-*/ic_launcher.png` masih menggunakan ikon default bawaan starter template Flutter.
   - Perlu digenerate ulang menggunakan logo resmi dari `assets/images/guyub_logo.png` (misalnya memakai `flutter_launcher_icons`).
2. **Label Nama Aplikasi**:
   - Di `android/app/src/main/AndroidManifest.xml`, ubah `android:label="guyub"` menjadi `"Guyub.id"` agar rapi di layar beranda ponsel pengguna.

---

## 4. Evaluasi Invarian Keamanan & Kualitas Kode (Status: LULUS)

| Kriteria / Invarian | Status | Keterangan |
|---|---|---|
| **Tidak ada tugas otomatis dari cuaca** (INV-01) | ✅ LULUS | Cuaca BMKG hanya menghasilkan *suggestion*, tugas aktif butuh persetujuan manual RT. |
| **Katalog tugas aman terkunci** (INV-02) | ✅ LULUS | Instruksi keselamatan dan rincian tugas terkunci sesuai versi template yang disetujui. |
| **Partisipasi sukarela** (INV-03) | ✅ LULUS | Aksi *Saya Ikut* dan *Tidak Ikut* netral, tidak ada skor, leaderboard, maupun denda. |
| **Tidak ada tugas berbahaya** (INV-04) | ✅ LULUS | Dilarang masuk gorong-gorong deras atau instalasi listrik basah. |
| **Perlindungan Privasi / Anti PII** (INV-05) | ✅ LULUS | Validasi regex memblokir NIK, nomor HP, alamat lengkap, dan koordinat GPS presisi. |
| **Dukungan Mode Luring (Offline)** (INV-06) | ✅ LULUS | Tugas tersimpan, nomor darurat, dan banner staleness tetap dapat diakses tanpa sinyal. |
| **Sanitasi Bukti Foto** (INV-07) | ✅ LULUS | EXIF GPS dibuang di client + server; bukti dihapus otomatis setelah 30 hari. |
| **Usulan Warga Tetap Inert** (INV-08) | ✅ LULUS | Usulan warga hanya menjadi konteks tinjauan RT, tidak pernah otomatis aktif. |
| **Verifikasi Penyelesaian oleh RT** (INV-09) | ✅ LULUS | Pengiriman warga berstatus `Menunggu Verifikasi RT` sampai diverifikasi operator. |
| **Eskalasi Tetap Resmi** (INV-10) | ✅ LULUS | Tidak menggantikan 112/BPBD/Polri; mengarahkan ke nomor darurat nasional resmi. |

---

## 5. Checklist Tahapan Menuju Rilis Publik (Action Plan)

- [ ] **Langkah 1 (Native Android)**:
  - Tambahkan izin `INTERNET` ke `android/app/src/main/AndroidManifest.xml`.
  - Ubah `android:label` menjadi `Guyub.id`.
  - Pasang ikon launcher dari `assets/images/guyub_logo.png`.
- [ ] **Langkah 2 (Keystore)**:
  - Generate release keystore `.jks`.
  - Konfigurasi `android/key.properties` dan secret GitHub Actions.
- [ ] **Langkah 3 (Cloud Backend)**:
  - Buat project Firebase produksi di region `asia-southeast2`.
  - Deploy Functions, Firestore Rules, dan Storage Rules.
  - Setup Firebase App Check (Play Integrity).
- [ ] **Langkah 4 (Data Awal / Seeding)**:
  - Daftarkan komunitas RT pilot di `/rt_communities/{rtId}` beserta join code hash.
  - Seed katalog tugas aman yang disetujui di `/task_templates/`.
- [ ] **Langkah 5 (Build APK Produksi)**:
  - Jalankan build menggunakan target produksi:
    ```bash
    flutter build apk --release --target=lib/main_prod.dart \
      --dart-define=FIREBASE_API_KEY="..." \
      --dart-define=FIREBASE_APP_ID="..." \
      --dart-define=FIREBASE_MESSAGING_SENDER_ID="..." \
      --dart-define=FIREBASE_PROJECT_ID="..."
    ```
