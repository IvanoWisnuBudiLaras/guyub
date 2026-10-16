# Panduan Pengembangan & Pembagian Tanggung Jawab Tim Guyub.id

Dokumen ini mengatur alur kerja tim, konvensi branching, dan fokus tanggung jawab teknis untuk pengembangan Guyub.id.

---

## 1. Pembagian Tanggung Jawab Tim

Tanggung jawab di bawah ini bersifat **dominan**, bukan ownership eksklusif. Seluruh anggota tim tetap dapat berkontribusi dan mereview area lain melalui Pull Request.

### Zaki (Presentation & UI Engineering)
- **Fokus utama:** Layer `presentation/`.
- Menerjemahkan desain mockup proposal ke widget Flutter responsif.
- Komponen visual, theming (Material 3), aset, dan form input.
- Widget test untuk interaksi antarmuka pengguna.
- Menjaga kejelasan pesan Bahasa Indonesia dan hierarki peran (RT vs Warga).

### Nawfal (Application Logic & State Flow)
- **Fokus utama:** Layer `application/`.
- Manajemen state, viewmodel/controller, dan use-case workflows.
- Alur interaksi bisnis (misal transisi status tugas, validasi katalog aman).
- Unit test untuk business logic dan state flow.
- Memastikan tidak ada business logic yang bocor ke dalam widget UI.

### Ivano (Integration, Infrastructure & Verification)
- **Fokus utama:** Layer `data/` (boundary & infrastructure) dan `core/`.
- Konfigurasi environment, database lokal (`LocalStore`), dan integrasi Firebase/BMKG.
- Architecture review dan verifikasi kepatuhan terhadap Master PRD.
- Pengujian integrasi, offline resilience, and security test (`AT-*`, `SEC-*`, `OFF-*`).
- Pemeliharaan skrip CI/CD dan release verification (`tool/verify.sh`).

---

## 2. Aturan Branching Git

Penamaan branch **wajib** berdasarkan fitur atau jenis pekerjaan, **bukan** berdasarkan nama personal developer.

### Konvensi Nama Branch
- Fitur baru: `feat/<nama-fitur>-<aspek>`  
  Contoh: `feat/task-ui`, `feat/task-interaction`, `feat/bmkg-fetch`
- Perbaikan bug: `fix/<deskripsi-singkat>`  
  Contoh: `fix/offline-task-cache`
- Pembersihan/Fondasi/Tooling: `chore/<nama-pekerjaan>`  
  Contoh: `chore/project-foundation`, `chore/setup-ci`
- Dokumentasi: `docs/<nama-dokumen>`  
  Contoh: `docs/update-traceability`

### Contoh yang DILARANG:
- `branch-zaki` ❌
- `branch-nawfal` ❌
- `branch-ivano` ❌
- `update-code` ❌

---

## 3. Gerbang Verifikasi Sebelum Merge (Verification Gate)

Sebelum mengajukan Pull Request atau menggabungkan kode ke branch utama (`main`), seluruh anggota tim wajib menjalankan satu perintah verifikasi:

```bash
./tool/verify.sh
```

Perintah ini memvalidasi:
1. `dart format` (kerapian kode seragam).
2. `flutter analyze` (nol warning/error analisa statis).
3. `flutter test` (seluruh unit dan widget tests lulus).
4. `flutter build apk --debug` (memastikan kode dapat dikompilasi menjadi APK Android).


## Pengujian aturan keamanan Firebase Emulator

Sebelum membuka PR, jalankan juga pengujian aturan Firestore:

```bash
./tool/test_firestore_rules.sh
```

Perintah ini memakai project demo dan emulator Auth/Firestore saja. Dibutuhkan Node.js 22 dan Java 21+. Tidak ada data atau layanan Firebase produksi yang digunakan. CI menjalankan perintah ini setelah `./tool/verify.sh`. Untuk callable Functions dan sesi warga, jalankan `./tool/test_functions.sh`; skrip ini menguji service lalu menjalankan Auth/Firestore/Functions Emulator dengan project demo. Functions Emulator disables App Check enforcement only for demo tests; production resident callables require the Android app to be registered with Firebase App Check and use Play Integrity.

## Pengujian lapisan callable di dua runtime

Lapisan callable dapat dijalankan lewat Cloud Functions **atau** lewat adapter HTTP mandiri
(`functions/server/http_adapter.js`). Keduanya membaca daftar callable yang sama dari
`functions/src/dispatch.js`, dan seluruh perilaku ada di `functions/src/app.js` — jadi tidak
ada logika yang boleh ditulis dua kali.

```bash
./tool/test_callable_adapters.sh
```

Skrip ini menjalankan emulator Auth/Firestore/Storage, menyalakan adapter HTTP, lalu menguji:
seam transport, gerbang App Check, dan alur penuh operator → warga → verifikasi. Terakhir,
klien HTTP Dart (`test/core/network/http_adapter_contract_test.dart`) diuji terhadap adapter
sungguhan itu. Tidak ada sisi yang di-mock.

Menambah callable baru: tambahkan method di service, lalu satu baris di
`functions/src/dispatch.js` (atau `customCallables` di `app.js` bila bentuk argumennya tidak
standar). Kedua adapter mengikutinya otomatis. `dispatch.js` hanya mengizinkan dua bentuk
argumen — `service(data)` dan `service(auth, data)`; bentuk lain harus ditulis tangan agar
tidak salah diklasifikasi diam-diam.

## Pengujian e2e di perangkat Android

Suite `e2e/` menjalankan alur nyata di emulator Android terhadap APK debug yang terpasang.
Tidak memakai model: `e2e/e2e.config.ts` tidak mendeklarasikan blok `agents`.

```bash
cd e2e && npm install
flutter build apk --debug && flutter install   # APK harus terpasang lebih dulu
./tool/test_e2e_android.sh tests/operator-flow.e2e.ts
```

Butuh Node.js 22.22.3+/24.8+, Android SDK dengan emulator, dan AVD bernama `guyub_e2e`
(di-pin di `e2e/e2e.config.ts`). Suite ini tidak dijalankan CI karena memerlukan emulator.

Skrip runner menyalakan emulator Firebase, menyemai RT/template/kampanye lewat callable
sungguhan, menghapus sesi tersimpan, lalu menjalankan suite yang diminta. Jalankan **satu
suite per pemanggilan**; menjalankan keempatnya berurutan di satu emulator menghabiskan
tenaganya — snapshot helper Android mulai gagal setelah sekitar empat tes.

| Suite | Menguji |
|---|---|
| `tests/operator-flow.e2e.ts` | Login operator, katalog aman, slot draf, draf inert sampai diaktifkan |
| `tests/task-cycle.e2e.ts` | Siklus penuh: warga kirim penyelesaian, operator verifikasi |
| `tests/offline-active-task.e2e.ts` | Tugas + instruksi keselamatan terbaca saat mode pesawat |
| `tests/rt-history.e2e.ts` | Riwayat tugas RT, penutupan eksplisit, linimasa peristiwa |
| `tests/offline-emergency.e2e.ts` | Rute Darurat terbuka offline tanpa mengarang data |

**Menulis tes baru:** `Key` milik widget Flutter tidak terlihat oleh driver, dan banyak
layar menggabungkan label dengan detailnya dalam satu node aksesibilitas — jadi gunakan
teks yang tampil, dan regex bila satu node memuat beberapa baris. Layar entry warga dan
operator memulihkan sesi secara **asinkron** saat dibuka, jadi tunggu restore selesai
sebelum memutuskan layar mana yang sedang aktif; tanpa itu, tes mengisi form yang akan
hilang dan gagal dengan galat verifikasi `fill` yang menyesatkan.

### Prasyarat khusus host Windows

Dua hal ini hanya berlaku saat mengembangkan di Windows; CI (ubuntu) tidak terpengaruh.

1. **Daemon `agent-device` gagal start.** Ia membaca identitas proses lewat
   `powershell.exe` dengan batas 2000 ms, sedangkan Windows PowerShell 5.1 memerlukan
   ~2.3 s. Perbaikannya: sediakan PowerShell 7 di `PATH` dengan nama `powershell.exe`.
2. **Build APK gagal dengan "Could not close incremental caches".** Penyebabnya pub cache
   di drive `C:` sedangkan project di drive lain, sehingga Kotlin tidak dapat menghitung
   path relatif. Jalankan `./gradlew assembleDebug -Pkotlin.incremental=false` dari
   `android/`. Jangan masukkan flag ini ke `android/gradle.properties`: di CI keduanya satu
   drive, jadi flag itu hanya memperlambat tanpa manfaat.

