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

---

## 4. Isu yang Telah Diselesaikan (Resolved Issues)

### [RESOLVED] Anomali Desain Overflow Horizontal pada Dropdown Dukungan Warga RT
- **Lokasi**: `lib/features/assistance/presentation/proxy_resident_screen.dart`, `task_draft_screen.dart`, `resident_proposal_review_screen.dart`
- **Gejala**: Teks judul tugas aktif panjang seperti *"Siapkan Tas Siaga & Dokumen Penting"* memicu peringatan visual `A RIGHT OVERFLOWED BY 23 PIXELS` pada dropdown picker di dalam kartu dukungan warga.
- **Penyebab**: `DropdownButtonFormField` belum memiliki properti `isExpanded: true` dan item teks belum dibatasi `overflow: TextOverflow.ellipsis`.
- **Solusi**: Diterapkan `isExpanded: true` dan `overflow: TextOverflow.ellipsis` pada seluruh dropdown terkait (relawan, pilihan partisipasi, dan pemilihan tugas aktif).

### [RESOLVED] Notifikasi Verifikasi Gagal dan Desinkronisasi Metrik Antrean di Dashboard Operator
- **Lokasi**: [task_response_screens.dart](file:///d:/project/guyub/lib/features/tasks/presentation/screens/task_response_screens.dart), [operator_home_screen.dart](file:///d:/project/guyub/lib/features/auth/presentation/screens/operator_home_screen.dart), [firebase_task_response_boundary.dart](file:///d:/project/guyub/lib/features/tasks/data/firebase_task_response_boundary.dart), [firebase_callable_client.dart](file:///d:/project/guyub/lib/core/network/firebase_callable_client.dart), [standalone_demo_service.dart](file:///d:/project/guyub/lib/core/demo/standalone_demo_service.dart)
- **Gejala**: Saat operator memverifikasi penyelesaian tugas warga, muncul snackbar *"Verifikasi gagal. Coba lagi."* padahal backend sudah sukses memverifikasi, dan metrik dashboard menampilkan data statis/hardcoded dari proposal mockup (`Pak Hendra`, `Bu Sari`, `12` Selesai, `14 dari 32 Rumah Tangga siap`, `Target: 28 Agustus`, `8/14 warga selesai`).
- **Penyebab**: 
  1. Exception handling di `_verify` langsung menampilkan SnackBar gagal bila terjadi exception apa pun tanpa memeriksa apakah record sebenarnya telah berhasil diverifikasi dan keluar dari antrean (`listPendingVerifications`).
  2. `FirebaseTaskResponseErrorMapper` belum menormalisasi kode error callable (misal `FAILED_PRECONDITION` atau `failed_precondition` dengan underscore/huruf besar) dan belum menangani pesan status verifikasi.
  3. Di mode demo standalone, generator `uploadResidentTaskEvidence` sempat menghasilkan format yang tidak sesuai regex 40-karakter hex sehingga memicu `FormatException` saat diparsing kembali.
  4. Komponen dashboard operator sebelumnya masih menggunakan teks dummy statis dari mockup proposal alih-alih data dinamis yang tersinkronisasi dari controller/backend.
- **Solusi**: 
  1. Mengimplementasikan double-check antrean pada blok `catch` di `_verify`: jika item sudah tidak ada di antrean tertunda, sistem mendeteksinya sebagai keberhasilan (*"Penyelesaian telah diverifikasi RT."*) dan memanggil `_reload()`.
  2. Menormalisasi kode error callable (`toLowerCase().replaceAll('_', '-')`) dan menangani pesan yang mengandung indikator verifikasi.
  3. Memperbaiki format evidence ID demo menjadi 40-karakter hex valid (`[a-f0-9]{40}`).
  4. Menyinkronkan seluruh elemen UI Dashboard Operator dengan data riil:
     - Kartu *"Menunggu Verifikasi"* terikat ke item antrean pertama (`_firstPendingRecord` dengan nama warga, judul tugas, waktu kirim lokal, dan indikator foto bukti).
     - Tile *"Selesai"* mengambil total dari riwayat tugas RT (`_completedTasksCount`).
     - Kartu *"Kesiapan Rumah Tangga"* menghitung persentase dinamis dari total warga terdaftar dan warga yang telah menyelesaikan tugas.
     - Kartu *"Tugas Terkini"* dan *"Target"* menghitung sisa waktu dan batas tanggal sebenarnya dari `ActiveTaskCampaignRecord.deadline`.
     - Header Operator menampilkan nama profil pengguna atau fallback ke label peran resmi (`profile.role.label`), bukan nama statis.

