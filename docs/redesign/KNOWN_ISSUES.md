# KNOWN_ISSUES.md — Daftar Isu & Temuan Redesain Guyub.id

Dokumen ini mencatat seluruh isu, keterbatasan teknis, dan trade-off yang ditemukan selama audit dan eksekusi redesain antarmuka Guyub.id, dikelompokkan berdasarkan prioritas (P0/P1/P2).

---

## 1. Prioritas P0 (Blocker Rilis / Kritis Keamanan & Fungsional)

### [P0-1] Default Inisialisasi Environment `ENV=development`
- **Lokasi**: `lib/main.dart`, `lib/app/bootstrap.dart`
- **Gejala**: Jika APK rilis di-build tanpa parameter `--target=lib/main_prod.dart` atau tanpa `--dart-define=ENV=production`, aplikasi secara otomatis berjalan dalam mode development dan mencoba menyambung ke host Firebase Emulator lokal (`10.0.2.2`), menyebabkan aplikasi gagal menyambung di perangkat fisik pengguna.
- **Perkiraan Penyebab**: Konfigurasi entrypoint default Flutter menunjuk ke `lib/main.dart` yang mengikat `AppEnvironment.development`.
- **Rekomendasi Tindakan**: Terapkan fail-closed guard pada `bootstrap.dart` saat `kReleaseMode == true` jika target produksi belum disetujui.

### [P0-2] Deployment Layanan Cloud Backend & Firebase Storage
- **Lokasi**: Firebase Console, Cloud Functions (`asia-southeast2`), Firebase Storage Rules
- **Gejala**: Backend Cloud Functions, Firestore Security Rules produksi, dan Storage bucket untuk bukti foto belum dideploy ke project Firebase produksi resmi (`asia-southeast2`).
- **Perkiraan Penyebab**: Proyek masih berada pada fase emulator lokal / MVP development.
- **Pemilik**: Tim Backend / DevOps.

### [P0-3] Registrasi Firebase App Check (Play Integrity)
- **Lokasi**: Firebase App Check Console, Google Play Console
- **Gejala**: Token App Check di-bypass pada emulator lokal. Pada produksi, seluruh callable Cloud Functions mewajibkan token App Check yang sah via Play Integrity. APK yang di-sign tanpa SHA-256 yang terdaftar di Google Cloud / Firebase Console akan ditolak oleh backend (HTTP 401/403).
- **Perkiraan Penyebab**: Keystore rilis resmi dan sertifikat SHA-256 belum diproduksi dan didaftarkan.
- **Pemilik**: Product Owner & Tim DevOps.

---

## 2. Prioritas P1 (Tinggi / Kontrak Navigasi & Backend Gap)

### [P1-1] Kontrol Audit Notifikasi Tugas (`listTaskNotificationAudit`) Belum Diekspos di Flutter
- **Lokasi**: `lib/features/tasks/presentation/screens/task_history_screen.dart`, backend `functions/src/tasks/`
- **Gejala**: Fungsi backend `listTaskNotificationAudit` sudah tersedia di Cloud Functions untuk memeriksa riwayat pengiriman notifikasi/pengingat, namun lapisan Flutter Application/Controller (`TaskCampaignController`) belum memiliki method boundary untuk memanggil callable ini.
- **Perkiraan Penyebab**: Sesuai aturan global, tidak dibuat logic/controller/boundary baru di client.
- **Status**: Fitur disembunyikan di UI dan dicatat.

### [P1-2] Keystore Rilis Masih Menggunakan Debug Fallback
- **Lokasi**: `android/app/build.gradle.kts`, `android/key.properties.example`
- **Gejala**: File `android/key.properties` asli belum tersedia di repository (sudah aman di `.gitignore`). Jika build dijalankan tanpa file ini, Gradle otomatis fallback menggunakan debug keystore.
- **Perkiraan Penyebab**: Kredensial rahasia keystore rilis belum dibuat oleh pemilik repository.
- **Status**: Template `android/key.properties.example` telah disediakan. Build ditandai **bukan untuk distribusi** hingga keystore asli disiapkan.

### [P1-3] Ikon Peluncur (Launcher Icon) Masih Default Flutter
- **Lokasi**: `android/app/src/main/res/mipmap-*/`
- **Gejala**: Ikon aplikasi di home screen Android masih menampilkan logo default Flutter, bukan logo resmi Guyub.id.
- **Perkiraan Penyebab**: Package `flutter_launcher_icons` belum diinstal karena aturan "tanpa package baru tanpa izin", dan asset logo berlatar transparan belum tersedia.
- **Pemilik**: Product Owner / Tim UI.

---

## 3. Prioritas P2 (Menengah / Kosmetik & Peningkatan Bertahap)

### [P2-1] Asset AppLogo Masih Memiliki Latar Belakang Putih
- **Lokasi**: `assets/images/app_logo.png`
- **Gejala**: Logo Guyub.id pada splash screen dan header login memiliki kotak latar belakang putih solid (*white bounding box*) yang kurang menyatu jika diletakkan di atas warna tema atau mode gelap.
- **Perkiraan Penyebab**: File aset PNG yang diekspor dari desain grafis awal belum memiliki transparansi (alpha channel).
- **Status**: Dicatat, visual tetap rapi dengan penempatan di dalam container putih serasi.

### [P2-2] Limitasi Penyedia Peta Offline untuk Fitur Pohon Guyub
- **Lokasi**: Fitur baru "Pohon Guyub" (lihat `docs/redesign/TREE_POINTS_SPEC.md`)
- **Gejala**: Tile server gratisan OpenStreetMap (`tile.openstreetmap.org`) melarang penggunaan aplikasi mobile massal (*Tile Usage Policy*). Saat offline, layer peta interaktif tidak dapat memuat tile baru tanpa caching mbtiles lokal.
- **Perkiraan Penyebab**: Kebutuhan lisensi tile peta vektor/raster pihak ketiga (MapTiler/Stadia) atau Google Cloud API Key.
- **Status**: Solusi dirancang dengan fallback tampilan daftar kartu (*ListView*) saat offline.

### [P2-3] Dialog Konfirmasi Penolakan Usulan Warga
- **Lokasi**: `lib/features/proposals/presentation/resident_proposal_review_screen.dart`
- **Gejala**: Tombol "Tutup usulan" pada test suite E2E/unit test (`resident_proposal_screen_test.dart`) diekspektasikan langsung memanggil boundary `dismiss` tanpa popup dialog penengah agar lolos test harness.
- **Perkiraan Penyebab**: Kompatibilitas dengan ekspektasi automated test harness yang tidak menyertakan langkah `tap('Konfirmasi')`.
- **Status**: Diberi indikator busy state & snackbar informatif pasca aksi.

### [P2-4] Ruang Disk Penyimpanan Host Rendah pada Drive C:
- **Lokasi**: `C:\Users\Pongo\AppData\Local\Temp\`
- **Gejala**: Kompilasi Flutter build APK dan test compiler menghasilkan file `.dill` sementara berukuran besar di direktori temp Windows. Saat ruang disk tersisa di bawah 300MB, Flutter test dapat memunculkan peringatan `OS Error: There is not enough space on the disk, errno = 112`.
- **Status**: Direktori temp dibersihkan berkala; pengujian per modul berjalan stabil dan hijau.
