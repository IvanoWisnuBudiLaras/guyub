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
