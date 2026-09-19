# Guyub.id — Sistem Kesiapsiagaan Banjir Komunitas RT/RW

Guyub.id adalah aplikasi koordinasi kesiapsiagaan banjir warga berbasis rukun tetangga (RT/RW). Aplikasi ini memfasilitasi gotong royong terstruktur, pembagian tugas mandiri yang aman, pemantauan peringatan dini BMKG, serta jalur informasi darurat warga secara offline-ready.

---

## 1. Gambaran Project Guyub.id
Guyub.id dirancang bukan sebagai mesin prediksi banjir instan atau pengganti tim SAR/BNPB, melainkan sebagai sistem orkestrasi persiapan warga sebelum bencana terjadi.
- **Katalog Tugas Aman**: Warga hanya menerima tugas dari katalog aman yang telah disetujui (dilarang membersihkan gorong-gorong berbahaya atau mendekati arus deras).
- **Partisipasi Sukarela**: Warga bebas memilih ikut atau menolak tugas tanpa penalti sosial atau sistem peringkat.
- **Privasi Terjaga**: Dilarang mengumpulkan NIK, alamat lengkap, atau koordinat GPS presisi warga.
- **Tahan Offline**: Tugas yang tersinkronisasi, kontak darurat, dan titik kumpul tetap dapat diakses tanpa koneksi internet.

---

## 2. Platform Target
- **Android (Prioritas Utama / Release Gate MVP)**: Target utama rilis dan verifikasi build wajib (`flutter build apk --debug`).
- **iOS (Kompatibel)**: Struktur folder dan dukungan iOS tetap dipertahankan. Seluruh shared Dart code dijaga agar platform-agnostic.

---

## 3. Arsitektur: Decoupled Feature-First Layered Monolith
Aplikasi dibangun sebagai satu aplikasi monolith Flutter terstruktur menggunakan pendekatan **Feature-First** dengan batasan infrastruktur yang decoupled:

- **Bukan Clean Architecture berlebihan**: Menghindari generic repository universal, use-case class untuk operasi trivial, atau factory berlapis.
- **Isolasi Boundary**: Provider infrastruktur (Firebase, SQLite, HTTP client) berada di balik antarmuka adapter (`core/database`, `core/network`).
- **Lapisan Fitur**:
  ```text
  presentation (UI Screen, Widget, Form)
      ↓
  application (Service, Workflows, State Controller)
      ↓
  repository / boundary (Interface Kontrak Data)
      ↓
  data / infrastructure (Adapter Remote / LocalStore)
  ```

---

## 4. Aturan Arah Dependensi (Dependency Direction)
1. **Unidirectional**: Presentation hanya boleh mengakses Application layer.
2. **Larangan Bocor Infrastruktur**: Widget UI dilarang mengimpor Firebase SDK, SQLite/Drift, atau HTTP library langsung.
3. **Data Implements Interface**: Data layer mengimplementasikan antarmuka yang didefinisikan pada application/boundary.
4. **Core Independence**: Core layer tidak boleh bergantung pada fitur bisnis apa pun.

---

## 5. Struktur Folder Project

```text
lib/
├── app/                  # Perakitan aplikasi (wiring), tema, router, & bootstrap
│   ├── app.dart          # Root widget GuyubApp & smoke screen Phase 0
│   ├── bootstrap.dart    # Orkestrasi startup & penyuntikan AppConfig
│   ├── router.dart       # Routing table deklaratif
│   └── README.md
│
├── core/                 # Fondasi cross-cutting domain-agnostic
│   ├── config/           # AppConfig & AppEnvironment (dev, test, prod)
│   ├── database/         # LocalStore interface & adapter (SharedPrefs, InMemory)
│   ├── network/          # Kontrak NetworkClient HTTP boundary
│   ├── result/           # Result<T> (Success/Failure) & hierarki AppError
│   ├── sync/             # SyncBoundary untuk antrean mutasi offline
│   └── README.md
│
├── features/             # Modul domain fungsional (feature-first)
│   ├── assistance/       # Dukungan warga rentan & status proxy helper
│   ├── auth/             # Sesi operator RT/RW & join-code warga
│   ├── emergency/        # Direktori darurat offline & rute eskalasi resmi
│   ├── evidence/         # Bukti foto opsional & sanitasi metadata EXIF (Phase 8)
│   ├── history/          # Riwayat kesiapsiagaan level RT yang persisten
│   ├── proposals/        # Usulan warga yang memerlukan review RT
│   ├── tasks/            # Lifecycle tugas gotong royong & safe catalog
│   ├── weather/          # Integrasi BMKG Open Data & suggestion generator (Phase 4)
│   └── README.md
│
├── firebase_options.dart # Konfigurasi platform Firebase
├── main.dart             # Default entrypoint (membaca flag ENV)
├── main_dev.dart         # Entrypoint eksplisit lingkungan Development
└── main_prod.dart        # Entrypoint eksplisit lingkungan Production
```

---

## 6. Environment & Konfigurasi Runtime
Aplikasi membedakan konfigurasi runtime menjadi tiga profil melalui `AppConfig`:
- **`development`**: Menggunakan konfigurasi lokal dengan Firebase Emulator untuk Auth (9099) dan Firestore (8080) pada IP `10.0.2.2` untuk Android.
- **`test`**: Mode isolasi tanpa koneksi jaringan/Firebase untuk automated tests yang deterministik.
- **`production`**: Mode rilis nyata tanpa emulator.

*Aturan Keamanan (SEC-06)*: Seluruh secret produksi, keystore, dan environment credentials tidak di-commit ke Git (dikecualikan pada `.gitignore`).

---

## 7. Cara Menjalankan Project

### Mode Pengembangan (Development / Emulator)
```bash
flutter run -t lib/main_dev.dart
# atau dengan flag compile-time:
flutter run --dart-define=ENV=development
```

### Mode Produksi (Production)
```bash
flutter run -t lib/main_prod.dart
# atau:
flutter run --dart-define=ENV=production
```

---

## 8. Cara Menjalankan Verifikasi Terpadu (Unified Gate)
Seluruh tim wajib menjalankan satu entrypoint verifikasi sebelum melakukan merge ke branch `main`:

```bash
./tool/verify.sh
```

Perintah ini secara berurutan mengeksekusi:
1. `dart format --output=none --set-exit-if-changed .`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --debug`

---

## 9. Cara Menjalankan Pengujian Otomatis (Tests)

Menjalankan seluruh unit test dan widget test baseline:
```bash
flutter test
```

Menjalankan subkumpulan test spesifik:
```bash
# Test Core (Config, Result, LocalStore)
flutter test test/core/

# Test App (Widget & Bootstrap)
flutter test test/app/
```

---

## 10. Status Backend & Cloud Provider: DEFERRED

### Firebase Cloud Functions
**Status: DEFERRED (Ditunda secara eksplisit pada Phase 0).**
- **Alasan**: Keputusan arsitektur serverless provider backend masih dalam evaluasi dan paket Firebase Spark (Gratis) tidak mendukung Cloud Functions tanpa aktivasi kartu kredit (Blaze Plan).
- **Ketentuan**: Tidak ada inisialisasi folder `functions/`, emulator Functions, ataupun dependensi Cloud Functions yang dibuat pada Phase 0.
- **Boundary**: Kebutuhan scheduled job cuaca BMKG (Phase 4) didesain sebagai boundary layanan mandiri tanpa membocorkan detail infrastruktur ke presentation layer.

### Firebase Cloud Storage
**Status: DEFERRED / NOT A PRODUCTION PROVIDER.**
- **Alasan**: Firebase Spark Plan tidak memungkinkan penggunaan Cloud Storage untuk beban produksi tanpa Blaze Plan.
- **Ketentuan**: Konfigurasi Storage emulator dihapus dari baseline Phase 0 dan tidak dianggap sebagai keputusan produksi.
- **Boundary**: Abstraksi penyimpanan bukti foto (`evidence`) tetap dipertahankan pada application/data layer agar provider konkret (lokal/S3-compatible/alternatif) dapat diputuskan pada **Phase 8**.

---

## 11. Dokumentasi API Dart (`dart doc`)
Public API penting pada core dan app layer telah didokumentasikan menggunakan standar Dartdoc (`///`) dalam Bahasa Indonesia.

Untuk membuat situs dokumentasi HTML lokal:
```bash
# Uji coba validitas dokumentasi tanpa generate file:
dart doc --dry-run

# Menghasilkan direktori dokumentasi (tersimpan di doc/api/):
dart doc
```
Folder `doc/api/` telah dimasukkan ke dalam `.gitignore` agar tidak mengotori riwayat commit Git.
