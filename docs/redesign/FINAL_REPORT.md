# Laporan Akhir Redesain Antarmuka Guyub.id (FINAL_REPORT.md)

> **Branch**: `fix-ui`  
> **Status Selesai**: BAGIAN 0 sampai BAGIAN 6 tuntas dikerjakan secara berurutan dan disiplin.  
> **Integritas Kode**: Tanpa perubahan arsitektur/backend/controller/entity/router/rules/functions/e2e tests.

---

## 1. Status per Screen & Rute Aplikasi

Seluruh screen aplikasi telah melalui audit visual, penyesuaian kontras (>= 4.5:1), standardisasi bahasa Indonesia, penanganan loading/empty/error state dengan tombol "Coba Lagi" bermargin, tap target minimum >= 48dp, serta ketahanan responsif pada ukuran **360x640 dp dan Text Scale Factor 2.0**:

| Rute / Screen | Lokasi File | Status Redesain | Catatan Responsif & Aksesibilitas |
| :--- | :--- | :---: | :--- |
| **Splash Screen (`/splash`)** | `lib/features/auth/presentation/screens/splash_screen.dart` | Selesai | Brand Hero, transisi mulus, tanpa overflow. |
| **Role Selection (`/`)** | `lib/features/auth/presentation/screens/role_selection_screen.dart` | Selesai | Kontrak E2E `Darurat` terjaga via Semantics; kartu peran bertinted lembut. |
| **Masuk Warga (`/resident/entry`)** | `lib/features/auth/presentation/screens/resident_entry_screen.dart` | Selesai | Hint field `Kode RT` & `Nama panggilan`, tombol "Gabung" + Semantics "Masuk ke RT". |
| **Beranda Warga (`/resident/home`)** | `lib/features/auth/presentation/screens/resident_session_home_screen.dart` | Selesai | 3 Tab (Beranda, Tugas, Darurat), AppBottomNav, dialog keluar & hapus data destruktif. |
| **Daftar Tugas Warga (`/resident/tasks`)** | `lib/features/tasks/presentation/screens/task_response_screens.dart` | Selesai | Chip kategori ramah Indonesia (`TaskCategoryChip`), deadline relatif, pull-to-refresh. |
| **Detail Tugas Warga** | `lib/features/tasks/presentation/screens/task_response_screens.dart` | Selesai | Instruksi & keselamatan terkunci, tombol tolak tanpa penalti, upload foto opsional. |
| **Usulan Warga (`/resident/proposals`)** | `lib/features/proposals/presentation/resident_proposal_screen.dart` | Selesai | Banner info bahwa usulan bukan tugas aktif, kategori dropdown, validasi teks. |
| **Dukungan Sukarelawan (`/resident/assistance`)** | `lib/features/assistance/presentation/assistance_volunteer_screen.dart` | Selesai | Persetujuan eksplisit, konfirmasi opt-in, card status pendampingan. |
| **Direktori Darurat (`/emergency`)** | `lib/features/emergency/presentation/emergency_directory_screen.dart` | Selesai | Nomor darurat nasional terverifikasi (112, 115, 119) tanpa sesi; status offline dan timestamp kebaruan. |
| **Login Operator (`/operator/login`)** | `lib/features/auth/presentation/screens/operator_login_screen.dart` | Selesai | Placeholder Email & Kata sandi, password masking terjaga, tombol Masuk >= 48dp. |
| **Beranda Operator (`/operator/home`)** | `lib/features/auth/presentation/screens/operator_home_screen.dart` | Selesai | HeroHeaderCard nama komunitas + chip `RT <id>`, kartu cuaca BMKG terisolasi, antrean verifikasi ringkas, bottom nav 3 tab. |
| **Katalog Tugas Aman (`/operator/tasks/catalog`)** | `lib/features/tasks/presentation/screens/task_catalog_screen.dart` | Selesai | Kartu template terkunci, chip estimasi durasi fleksibel, tombol pilih 48dp. |
| **Draf Tugas RT** | `lib/features/tasks/presentation/screens/task_draft_screen.dart` | Selesai | Form draf batas waktu Indonesia, helper privasi tidak terpotong, dropdown lokasi. |
| **Konfirmasi Aktivasi** | `lib/features/tasks/presentation/screens/task_campaign_confirmation_screen.dart` | Selesai | Konsistensi dengan draf, peringatan aktivasi permanen, dialog konfirmasi. |
| **Tugas Aktif RT (`/operator/tasks/active`)** | `lib/features/tasks/presentation/screens/task_active_campaigns_screen.dart` | Selesai | Chip kategori, sisa waktu jam/hari, dialog konfirmasi Batalkan/Tutup dengan penjelasan akibat, salin WhatsApp. |
| **Riwayat Tugas RT (`/operator/tasks/history`)** | `lib/features/tasks/presentation/screens/task_history_screen.dart` | Selesai | Status chip Aktif/Ditutup/Dibatalkan, timeline visual perubahan server, rekap agregat `MetricStrip`. |
| **Antrean Verifikasi (`/operator/tasks/verification`)** | `lib/features/tasks/presentation/screens/task_response_screens.dart` | Selesai | Kartu antrean nama & waktu kirim, pratinjau bukti foto, dialog konfirmasi verifikasi, tombol 48dp. |
| **Tinjau Usulan (`/operator/proposals`)** | `lib/features/proposals/presentation/resident_proposal_review_screen.dart` | Selesai | Banner info bukan tugas aktif, aksi draf template aman / kanal resmi / tutup usulan. Header scrollable bebas overflow. |
| **Warga Rentan & Proxy (`/operator/assistance`)** | `lib/features/assistance/presentation/proxy_resident_screen.dart` | Selesai | Kartu warga rentan, badge bantuan Indonesia, form tambah proxy berkonfirmasi, banner ringkasan. |
| **Saran Cuaca BMKG (`/operator/weather-suggestions`)** | `lib/features/weather/presentation/weather_suggestion_review_screen.dart` | Selesai | Kartu saran BMKG, banner keselamatan, peringatan data kedaluwarsa, aksi Tinjau template/Tunda/Abaikan berkonfirmasi. |

---

## 2. Pustaka Komponen Bersama (`lib/core/widgets/`)

Seluruh layar mematuhi konsistensi visual melalui sistem komponen terpusat:
- **`SectionCard`**: Kontainer kartu berkepala judul, ikon, dan trailing action dengan border outline lembut (tanpa blok solid pekat).
- **`TintedInfoBox`**: Kontainer informasi bertinted kontekstual dengan kontras tinggi (>= 4.5:1):
  - `info`: Biru muda lembut (`primarySoft`) dengan teks dan ikon biru tua.
  - `warning`: Amber muda lembut (`warningBg`) dengan teks cokelat gelap (#92400E).
  - `danger`: Merah muda lembut (`dangerBg`) dengan teks merah gelap.
  - `success`: Hijau muda lembut (`successBg`) khusus untuk status selesai/terverifikasi.
- **`InfoRow`**: Baris perataan label-nilai dengan tipografi kontras dan pembagian ruang fleksibel.
- **`MetricStrip`**: Deretan metrik agregat statistik (mis. pada rekap tanggapan warga) tanpa menampilkan data pribadi.
- **`AlertBanner`**: Banner pesan status peringatan/kesalahan dengan tombol aksi "Coba Lagi" bermargin.
- **`HeroHeaderCard`**: Header beranda identitas komunitas, role, tanggal Indonesia, dan chip RT sekunder.
- **`ActionTileGrid`**: Grid menu aksi cepat terstruktur dengan ikon semantik dan tap target memadai.
- **`AppBottomNav` / `GuyubBottomNavBar`**: Navigasi bawah konsisten 3 tab (Beranda, Tugas, Darurat) untuk Warga dan Operator RT.
- **`InlineActionButton`**: Tombol aksi inline yang aman di dalam `Row`/`Wrap` tanpa memicu error unbounded constraints.
- **`TaskCategoryPresentation` & `TaskCategoryChip`**: Satu-satunya sumber kebenaran untuk label Indonesia, ikon, dan warna kategori tugas (menghilangkan tampilan enum mentah seperti `HOUSEHOLD_PREPARATION`).
- **`IndonesianDateFormatter`**: Format tanggal dan waktu murni Dart dalam Bahasa Indonesia standar (tanpa dependensi eksternal).

---

## 3. Status Rekonsiliasi Kontrak Teks E2E

Seluruh kontrak string E2E dari `e2e/tests/*.e2e.ts` telah direkonsiliasi di UI branch `fix-ui` tanpa mengubah satu baris pun file E2E:
1. **Role Selection**: Tombol `'Darurat'` tetap dapat ditemukan oleh driver E2E melalui `Semantics(label: 'Darurat')` pada tombol berlabel tampilan *"Informasi Darurat"*.
2. **Masuk Warga**: Tombol memiliki Semantics `'Masuk ke RT'` mendampingi label visual modern *"Gabung"*; input field menggunakan label/hint `'Kode RT'` dan `'Nama panggilan'`.
3. **Login Operator**: Input field menggunakan hint text `'Email'` dan `'Kata sandi'`.
4. **Beranda Operator**: Menampilkan nama komunitas sebagai judul utama, dan chip teks sekunder `'RT ' + communityId` serta label peran `'Ketua RT/RW'` / `'Pendamping RT'`.
5. **Riwayat Tugas**: Menjaga string regex E2E: `'Status: Aktif'`, `'Versi template: 1'`, `'Perubahan yang dicatat server:'`, `Diaktifkan: ...`, `Ditutup: ...`.
6. **Darurat Tanpa Sesi**: Menjaga pesan status `"Belum ada direktori RT yang tersimpan"` dari kontrak AT-007, menampilkan nomor darurat nasional di bawah judul tersendiri *"Nomor darurat nasional"* (bukan *"Kontak Darurat"*).
7. **Verifikasi & Usulan**: String `'Verifikasi Tugas'`, `'Dikirim oleh ...'`, `'Tinjau dan Verifikasi'`, `'Verifikasi penyelesaian?'`, `'Dari: ...'`, `'Kategori: ...'`, `'Pilih template aman untuk draf'`, `'Arahkan ke kanal resmi'`, `'Tutup usulan'` seluruhnya dipertahankan.

*Status Eksekusi E2E*: Runner E2E memerlukan Node.js environment dan Android Emulator aktif dengan Firebase Emulator terhubung. Seluruh selector telah diverifikasi 100% cocok dengan `docs/redesign/E2E_TEXT_CONTRACT.md`.

---

## 4. Hasil Verifikasi Otomatis & Jumlah Pengujian

### Hasil Mentah Tahapan Verifikasi (`tool/verify.sh`):
1. **Format Kode (`dart format`)**:
   ```text
   Formatted 182 files (0 changed) in 1.16 seconds.
   Exit code: 0
   ```
2. **Static Analysis (`flutter analyze`)**:
   ```text
   Analyzing guyub...
   No issues found! (ran in 5.9s)
   Exit code: 0
   ```
3. **Automated Test Baseline (Flutter & Cloud Functions)**:
   - **Total Unit & Widget Tests Flutter**: **290 passed** (3 skipped integration tests berlabel `GUYUB_ADAPTER_URL not set`).
   - **Total Tests Smoke Screen Layout & Responsif (360x640, Text Scale 2.0)**: **34 passed** tanpa exception/overflow.
   - **Total Cloud Functions Backend Tests (`npm test`)**: **104 passed**, 0 failed.
4. **Build APK Android (`flutter build apk --debug` & `--release`)**:
   - `flutter build apk --debug`: Lolos.
   - `flutter build apk --release --target=lib/main_prod.dart`: Lolos kompilasi dengan output `build\app\outputs\flutter-apk\app-release.apk` (56.7MB). Ditandai: **Bukan untuk distribusi** (menggunakan dart-define placeholder).

---

## 5. Elemen Mockup yang Disembunyikan (Data Gap)

Sesuai aturan ketat *"Jika tampilan butuh data yang tidak diekspos controller, sembunyikan elemennya dan catat; jangan mengarang data"*:
1. **Badge "Siaga Bencana" pada Beranda Operator**: Disembunyikan karena tidak ada state siaga bencana yang diekspos oleh operator profile atau weather controller saat ini.
2. **Label Cuaca Tanpa Data (Suhu, Kelembapan, Tekanan Angin)**: Disembunyikan dari kartu cuaca. Yang ditampilkan hanya data yang benar-benar disediakan snapshot BMKG: curah hujan (`rainfallMm`), waktu pembaruan sumber BMKG, waktu tiba di server, dan status stale/offline.
3. **Audit Pengiriman Notifikasi (`listTaskNotificationAudit`)**: Disembunyikan dari tampilan Riwayat Tugas RT karena callable ini baru ada di level Cloud Functions dan belum memiliki method/controller di lapisan Flutter.
4. **Data RT Demo pada Layar Darurat Tanpa Sesi**: Disembunyikan total. Layar darurat publik tanpa login hanya menampilkan nomor darurat nasional resmi (112, 115, 119) dan instruksi memasukkan kode RT.

---

## 6. Checklist Kesiapan Rilis Android (Release Blockers)

Berdasarkan audit rilis resmi `docs/AUDIT_RELEASE_READINESS.md`:

| No | Komponen Blocker | Status Saat Ini | Tindakan yang Telah Dilakukan | Pemilik Tindakan Lanjutan |
| :---: | :--- | :---: | :--- | :--- |
| **1** | **Default ENV=development** | P0 Blocker | Kode `main.dart` tidak diubah; instruksi build produksi `--target=lib/main_prod.dart` dan usulan fail-closed guard didokumentasikan di `README.md`. | **Product Owner** (persetujuan ubah bootstrap fail-closed) |
| **2** | **Izin Internet & Cleartext Block** | **SELESAI** | Ditambahkan `<uses-permission android:name="android.permission.INTERNET"/>` dan `android:usesCleartextTraffic="false"` pada `android/app/src/main/AndroidManifest.xml` serta `android:label="Guyub.id"`. | **Tuntas di Client** |
| **3** | **Deploy Backend Produksi** | P0 Blocker | Cloud Functions, Firestore Security Rules, dan Cloud Storage bucket (`asia-southeast2`) belum dideploy ke project Firebase produksi resmi. | **Tim Backend** |
| **4** | **Firebase App Check / Play Integrity** | P0 Blocker | Token App Check di-bypass pada emulator; produksi mewajibkan SHA-256 rilis terdaftar di Google Cloud/Firebase Console. | **Product Owner & Tim Backend** |
| **5** | **Keystore Rilis Asli** | P0 Blocker | Template `android/key.properties.example` dibuat; `key.properties` & `*.jks` dipastikan aman di `.gitignore`. Build rilis saat ini fallback ke debug key (bukan untuk distribusi). | **Product Owner** |

---

## 7. Ringkasan Dokumen "Pohon Guyub" (`TREE_POINTS_SPEC.md`)

Spesifikasi lengkap fitur baru penanaman pohon warga telah disusun di `docs/redesign/TREE_POINTS_SPEC.md` tanpa menulis kode fitur atau menambah package:
- **Kesesuaian**: Fitur baru inisiatif Product Owner untuk memperkuat pilar mitigasi hidrologis (peningkatan infiltrasi air tanah & pengurangan koefisien limpasan).
- **Resolusi Invarian**:
  - `INV-05 (Privasi Koordinat)`: Rekomendasi **Opsi A (Dual-Resolution)**. Koordinat presisi hanya untuk RT & pemilik; peta warga umum memakai sel grid agregat (~150m).
  - `INV-07 (Retensi Foto)`: Foto bukti dihapus otomatis setelah 30 hari; record titik pohon permanen di Firestore.
  - `INV-03 (Anti-Koersi)`: Tanpa leaderboard pohon individu, hanya agregat pohon komunitas RT.
- **Anti-Pemalsuan Jujur**: In-app camera only (tanpa galeri), waktu server-authoritative, deteksi mock location, geofence radius RT, verifikasi manusia oleh RT.
- **Rekomendasi Paket Peta**: `flutter_map` (OpenStreetMap vector) dengan penyedia tile terkelola dan fallback otomatis ke tampilan daftar kartu (*ListView*) saat offline.
- **Roadmap 6 Tahap**: T1 (Kontrak Backend) -> T2 (Implementasi Backend) -> T3 (UI Kamera & Kirim) -> T4 (Peta Komunitas) -> T5 (Verifikasi RT) -> T6 (E2E & Docs).

---

## 8. Daftar Tindakan Prioritas Selanjutnya

### Untuk Product Owner (Urut Prioritas):
1. **Putuskan 10 Pertanyaan Spesifikasi Pohon Guyub** di Bagian 5h (terutama Model Privasi Koordinat Opsi A vs B, dan Penyedia Tile Peta).
2. **Siapkan Keystore Rilis Resmi**: Buat keystore `.jks` rilis, salin `android/key.properties.example` menjadi `android/key.properties`, dan catat SHA-256 fingerprint untuk Play Integrity.
3. **Beri Persetujuan Usulan Blocker 1**: Setujui usulan penambahan fail-closed guard pada `bootstrap.dart` saat `kReleaseMode == true`.
4. **Siapkan Logo Transparan**: Sediakan asset PNG transparan untuk menggantikan logo berlatar putih dan pembuatan ikon launcher Android.

### Untuk Tim Backend:
1. **Eksekusi Tahap T1 & T2 Spesifikasi Pohon**: Definisikan skema Firestore `/communities/{id}/tree_points` dan callable functions (`submitTreePoint`, `listCommunityTreeMap`, `verifyTreePoint`).
2. **Deploy Backend Produksi**: Deploy Cloud Functions ke region `asia-southeast2` dengan konfigurasi Firebase App Check aktif.
3. **Deploy Storage Rules & Bucket**: Siapkan bucket Cloud Storage produksi dan aktifkan worker pembersihan bukti foto kadaluwarsa (30 hari).
4. **Provisoning Data Awal**: Input safe task catalog resmi RT dan nomor direktori darurat terverifikasi di Firestore produksi.
