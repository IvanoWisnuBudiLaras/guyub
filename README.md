# Guyub.id — Sistem Kesiapsiagaan Banjir Komunitas RT/RW

Guyub.id adalah aplikasi koordinasi kesiapsiagaan banjir warga berbasis rukun tetangga (RT/RW). Aplikasi ini memfasilitasi gotong royong terstruktur, pembagian tugas mandiri yang aman, konteks cuaca BMKG, serta jalur informasi darurat warga dengan dukungan offline bertahap. Dukungan offline belum lulus verifikasi perangkat/pilot.

---

## 1. Gambaran Project Guyub.id
Guyub.id dirancang bukan sebagai mesin prediksi banjir instan atau pengganti tim SAR/BNPB, melainkan sebagai sistem orkestrasi persiapan warga sebelum bencana terjadi.
- **Katalog Tugas Aman**: Warga hanya menerima tugas dari katalog aman yang telah disetujui (dilarang membersihkan gorong-gorong berbahaya atau mendekati arus deras).
- **Partisipasi Sukarela**: Warga bebas memilih ikut atau menolak tugas tanpa penalti sosial atau sistem peringkat.
- **Privasi Terjaga**: Dilarang mengumpulkan NIK, alamat lengkap, atau koordinat GPS presisi warga.
- **Dukungan Offline bertahap**: Cache tugas, direktori darurat, dan cuaca terakhir diberi label waktu sinkronisasi. Validasi mode pesawat/perangkat masih menjadi release gate; direktori darurat tidak berisi data produksi sampai kontak, titik kumpul, dan kanal resmi diverifikasi serta diprovisikan.

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
│   ├── app.dart          # Root widget GuyubApp & role-aware router
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
- **`development`**: Auth dan Firestore diarahkan ke Firebase Emulator (9099/8080). Aplikasi memakai project ID emulator `demo-guyub-development` dan key dummy; emulator yang mati tidak menyebabkan fallback ke Firebase produksi.
- **`test`**: Mode isolasi tanpa koneksi jaringan/Firebase untuk automated tests yang deterministik.
- **`production`**: Mode rilis nyata tanpa emulator.

*Aturan Keamanan (SEC-06)*: Seluruh secret produksi, keystore, dan environment credentials tidak di-commit ke Git (dikecualikan pada `.gitignore`).

---

## 7. Cara Menjalankan Project

### Mode Pengembangan (Development / Emulator)
Terminal pertama menjalankan emulator lokal:
```bash
npx --yes firebase-tools@15.32.1 emulators:start \
  --project demo-guyub-development --only auth,firestore,functions
```
Terminal kedua menjalankan aplikasi:
```bash
flutter run -t lib/main_dev.dart
# atau dengan flag compile-time:
flutter run --dart-define=ENV=development
```
Jika emulator tidak tersedia, aplikasi tetap membuka pilihan peran tetapi masuk operator gagal tertutup. Data autentikasi dan Firestore pengembangan tidak dikirim ke project produksi.

### Mode Produksi (Production)
Supply the Firebase client options from the protected build environment; they are not stored in the repository:
```bash
flutter run -t lib/main_prod.dart \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="$FIREBASE_MESSAGING_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID"
```
Without these values, the app fails closed and operator access remains unavailable. Do not use production options for development.

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

Menjalankan unit/widget test Flutter:
```bash
flutter test
```

Menjalankan subkumpulan test spesifik:
```bash
# Test Core (Config, Result, LocalStore)
flutter test test/core/

# Test App (Widget & Bootstrap)
flutter test test/app/

# Test alur operator, task, dan weather
flutter test test/features/
```

Aturan akses Firestore dan sesi warga diuji dengan Auth/Firestore/Functions Emulator (Java 21+ dan Node.js 22):
```bash
./tool/test_firestore_rules.sh
./tool/test_functions.sh
```

---

## 10. Status Backend & Cloud Provider

### Firebase Cloud Functions
**Status: resident sessions, RT-scoped task campaigns/cancellation/closure/history, resident responses, RT verification, and emergency-directory callables are implemented for Emulator; production deployment deferred.**
- `functions/` implements opaque resident-session callables; operator-only reviewed-template, draft, activation, active-list, cancellation, explicit closure, paginated RT-history, and privacy-safe lifecycle-event callables; RT-scoped resident task listing, JOIN/DECLINE, completion submission, verification, and aggregate response recap; and session-scoped emergency-directory reads. Functions, Auth, and Firestore emulators cover these boundaries.
- Production callables require Firebase App Check; the Android client uses Play Integrity. App Check is intentionally disabled only in the demo emulator and must be registered for the signed Android app before production use. Enrollment retries reuse a pending secure request ID so one attempt does not create duplicate resident profiles.
- Protected collections remain client-deny by Firestore rules. No human-reviewed real task template is provisioned; the catalog remains empty until trusted provisioning. Offline task cache/outbox/reconciliation, emergency-directory callables/cache, and cached weather display are implemented in code but still need Android airplane-mode and pilot validation. A server-side BMKG fetch/suggestion pipeline is implemented but has no provisioned source, rule, threshold, or pilot area; the Android card is not connected to that pipeline. No emergency contacts, assembly points, official routes, or BMKG values are seeded. No production function is deployed; FCM delivery, reminders, and escalation remain unimplemented. The evidence sanitization and cleanup code is emulator-tested but is not deployed to production.
- Production deployment and scheduled automation may require a Firebase billing/provider decision. This repository does not enable billing or deploy production infrastructure.

### Firebase Cloud Storage
**Status: EMULATOR-TESTED CODE; NOT A PRODUCTION PROVIDER.**
- Optional evidence upload, client/server metadata stripping, private Storage access, resident-scoped evidence deletion, and physical 30-day cleanup are implemented and covered by service/emulator tests.
- No Storage deployment or billing change was made. Production bucket setup, scheduled cleanup deployment, and retention validation remain external blockers.

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
