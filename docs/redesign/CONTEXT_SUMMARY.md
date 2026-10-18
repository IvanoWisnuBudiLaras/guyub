# CONTEXT SUMMARY — GUYUB.ID MVP REDESIGN

**Dokumen Ringkasan Bacaan Wajib & Konteks Sistem (Bagian 0)**  
*Tanggal: 18 Oktober 2026*  
*Cabang: `fix-ui`*  

---

## 1. Tujuan Produk, Nilai Inti & Batasan Sistem

Guyub.id adalah **sistem koordinasi kesiapsiagaan banjir tingkat RT/komunitas berbasis Android**.  
Aplikasi ini **BUKAN** mesin prediksi banjir tingkat RT, bukan sistem peringatan dini otomatis darurat, dan bukan pengganti kanal resmi pemerintah/SAR.

### Nilai Jual Utama (The Core Value Proposition)
1. **Otomasi Terkonfirmasi (*Human-in-the-Loop*)**: Pekerjaan berulang (penarikan data BMKG, evaluasi ambang hujan, pembuatan saran tugas, pengingat, penghapusan foto bukti) dijalankan otomatis oleh sistem, tetapi keputusan yang menyangkut keselamatan warga (aktivasi tugas, verifikasi penyelesaian) mutlak memerlukan konfirmasi manusia (Ketua RT / Pendamping).
2. **Katalog Tugas Aman Terkunci**: Tugas pencegahan banjir berasal dari katalog aman terstandarisasi yang instruksi inti dan instruksi keselamatannya terkunci. Warga atau operator tidak dapat membuat instruksi yang membahayakan.
3. **Pencatatan yang Melekat pada Entitas RT**: Riwayat kesiapsiagaan lingkungan bertahan lintas kepengurusan RT dan lintas kejadian bencana (berbeda dengan grup WhatsApp yang pesannya cepat tenggelam dan hilang saat pergantian pengurus).
4. **Data Minimal & Privasi Ketat**: Mengacu pada UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi (PDP). Tanpa NIK, tanpa alamat rumah lengkap, tanpa nomor telepon publik, dan tanpa koordinat GPS presisi warga.

---

## 2. Role & Hak Akses Pengguna

| Role | Mekanisme Autentikasi | Lingkup Hak Akses | Batasan Kunci |
|:---|:---|:---|:---|
| **Ketua RT/RW** | Firebase Authentication (Email & Kata Sandi) | Akses penuh operasional RT: aktivasi draf tugas, penutupan/pembatalan tugas, verifikasi penyelesaian warga, peninjauan usulan, pengelolaan data bantuan proxy. | Terikat pada `rtId` dokumen `/operators/{uid}`. Tidak dapat mengarang instruksi keselamatan baru di luar katalog. |
| **Pendamping RT** | Firebase Authentication (Email & Kata Sandi) | Sama dengan Ketua RT, dengan fokus operasional pada pendampingan warga rentan dan menerima push notification tugas (opt-in). | Terikat pada `rtId` dokumen `/operators/{uid}`. |
| **Warga Mandiri** | Kode RT aktif (kriptografis) + Nama panggilan mandiri (tanpa password/email) | Melihat tugas aktif RT, menyatakan keikutsertaan sukarela (*Saya Ikut* / *Tidak Ikut*), mengirim catatan & bukti foto pengerjaan, mengajukan usulan, opt-in kesediaan membantu sesama. | Sesi token lokal terenkripsi di `FlutterSecureStorage`, divalidasi server via SHA-256. Tidak dapat mengakses data pribadi warga lain. |
| **Relawan Warga (*Helper*)** | Turunan sesi Warga dengan opt-in `willingToHelp: true` | Menerima permintaan bantuan untuk mendampingi warga rentan terdekat, konfirmasi kesediaan (*ACCEPTED*/*DECLINED*), lapor status bantuan. | Sepenuhnya sukarela; dapat mundur sewaktu-waktu tanpa penalti atau perubahan status warga. |

---

## 3. Sepuluh Invarian Produk Non-Negosiasi (INV-01 s/d INV-10)

1. **INV-01: Tidak Ada Pengiriman Tugas Otomatis dari Ambang Cuaca.** Data BMKG hanya menghasilkan saran (*suggestion*). Tugas aktif wajib disetujui secara eksplisit oleh operator RT.
2. **INV-02: Tidak Ada Pembuatan Tugas Kritis Keselamatan Sembarangan.** Tugas berasal dari katalog aman terulas. Judul, instruksi inti, dan keselamatan terkunci per snapshot versi.
3. **INV-03: Partisipasi Sukarela.** Warga berhak memilih ikut atau tidak ikut. Dilarang ada skor kepatuhan, pemeringkatan (*leaderboard*), sanksi, atau bahasa koersif.
4. **INV-04: Dilarang Ada Tugas Berbahaya.** Template tugas dilarang mengarahkan warga masuk saluran air deras, menyentuh instalasi listrik basah, atau pekerjaan SAR darurat profesional.
5. **INV-05: Perlindungan Privasi Data Pribadi.** Dilarang menyimpan/meminta NIK, alamat rumah lengkap, dan koordinat GPS presisi warga di database maupun log.
6. **INV-06: Konten Kritis Wajib Dapat Diakses Mode Luring (*Offline-First*).** Tugas aktif tersimpan, snapshot cuaca terakhir + timestamp, nomor darurat, dan titik kumpul tetap terbaca tanpa internet.
7. **INV-07: Bukti Foto Bersifat Opsional & Sementara.** Metadata EXIF (termasuk GPS) wajib dibuang sebelum penyimpanan. Berkas bukti otomatis dihapus server setelah 30 hari.
8. **INV-08: Usulan Warga Wajib Melalui Peninjauan RT.** Usulan warga bersifat inert (konteks saja), tidak pernah otomatis menjadi tugas aktif.
9. **INV-09: Penyelesaian Tugas Memerlukan Verifikasi RT.** Pengiriman oleh warga berstatus *Menunggu Verifikasi RT* sampai operator memverifikasi; tidak ada penyelesaian otomatis sepihak.
10. **INV-10: Eskalasi Resmi Tetap ke Kanal Resmi.** Masalah di luar kapasitas gotong royong diarahkan ke kanal darurat pemerintah (112, BPBD, SP4N-LAPOR!, JAKI); Guyub.id tidak menggantikannya.

---

## 4. Matriks Acceptance Tests (AT-xxx) Kunci

- **AT-001**: Pembuatan draf tidak mengaktifkan kampanye; aktivasi butuh pemanggilan callable `activateTaskCampaign` terpisah.
- **AT-002**: Template katalog menyajikan instruksi inti dan instruksi keselamatan yang terkunci.
- **AT-003**: Operator hanya dapat mengatur batas waktu (di masa depan) dan jenis lokasi umum (opsional); tidak ada input teks instruksi bebas.
- **AT-004**: Warga dapat memilih *Saya Ikut* atau *Tidak Ikut* secara bebas; pilihan tidak ikut tidak menimbulkan denda.
- **AT-005**: Pengiriman pengerjaan warga tetap berstatus *Menunggu Verifikasi RT* hingga diverifikasi operator di antrean verifikasi.
- **AT-006**: Tugas aktif dan instruksi keselamatan tersinkron tetap dapat dibaca saat perangkat offline / mode pesawat; UI menyatakan status data tersimpan (cached).
- **AT-007**: Layar darurat dapat dibuka tanpa jaringan dan menyatakan statusnya; jika belum ada direktori tersimpan, UI tidak boleh mengarang data darurat.
- **AT-008**: Unggah foto bukti bersifat opsional; kegagalan unggah foto tidak memblokir pengiriman tanggapan tugas.
- **AT-009**: Cloud Storage dan metadata bukti foto dihapus otomatis saat mencapai retensi 30 hari.
- **AT-010**: Evaluasi ambang hujan BMKG hanya memicu dokumen `weather_suggestions`.
- **AT-011**: Kegagalan penarikan cuaca BMKG terbaru tidak boleh menghapus data valid terakhir (*never wipe last valid snapshot*).
- **AT-012**: Usulan warga masuk ke antrean `resident_proposals` dan hanya dapat dipetakan operator ke template katalog aman.
- **AT-013**: Pendaftaran warga rentan oleh operator (proxy) tidak meminta NIK atau alamat lengkap.
- **AT-014**: Pengiriman notifikasi push FCM mematuhi jendela waktu aman komunitas (default 06:00 - 21:00) kecuali status darurat.
- **AT-015**: Riwayat tugas adalah milik RT (`rtId`), bukan akun operator individu, dan timeline hanya mengekspos tipe event dan stempel waktu.
- **AT-016**: Ringkasan tugas untuk WhatsApp diekspor dalam format teks siap salin secara manual oleh operator untuk tugas aktif.
- **AT-020**: Kesediaan menjadi relawan memerlukan konfirmasi eksplisit dari warga tanpa tekanan (*explicit confirmation*).

---

## 5. Ringkasan Ekstraksi Proposal MAGE (`docs/MAGE 12_Tahap 1_AppDev...docx`)

Berdasarkan pembacaan biner dan ekstraksi XML (`word/document.xml`) langsung dari berkas asli proposal Microsoft Word:
- **Total Karakter Teks:** 24.563 karakter.
- **Hasil Pencarian Kata Kunci:**
  - `pohon`, `tree`, `penghijauan`, `menghijaukan`, `kepemilikan`, `vegetasi`, `resapan`, `biopori`, `pemalsuan`: **0 kemunculan**.
  - `peta`: **6 kemunculan** (semuanya merujuk pada integrasi data eksternal PetaBencana.id dan penyediaan peta titik kumpul evakuasi luring).
  - `koordinat`: **2 kemunculan** (P95: batasan ruang lingkup melarang publikasi koordinat; P99: batasan privasi melarang penyimpanan koordinat GPS warga).
  - `gps`: **1 kemunculan** (P99: larangan penyimpanan koordinat GPS warga mengacu UU PDP).
  - `titik`: **2 kemunculan** (P46: titik keputusan dipindahkan ke manusia; P131: penyediaan titik kumpul yang dapat dibuka tanpa internet).
  - `kamera`: **0 kemunculan**.
  - `foto`: **3 kemunculan** (P95: dilarang mempublikasikan foto warga; P114: Cloud Functions otomatis menghapus bukti foto kedaluwarsa; P130: foto bukti opsional, EXIF lokasi dibuang, retensi 30 hari).

### Kesimpulan Hubungan Proposal vs Fitur "Pohon Guyub":
Proposal MAGE tahap 1 **tidak pernah menjanjikan fitur kepemilikan pohon warga atau peta titik pohon**, bahkan proposal secara eksplisit melarang pencatatan GPS warga untuk melindungi privasi.  
Namun, sesuai **Keputusan Pengguna No. 1**, fitur ini **didefinisikan secara resmi sekarang** sebagai inisiatif pencegahan banjir melalui penanaman pohon lingkungan warga. Spesifikasi lengkap, resolusi benturan invarian privasi, dan rancangan arsitekturnya disusun pada **Bagian 5** (`docs/redesign/TREE_POINTS_SPEC.md`).

---

## 6. Ringkasan Kesiapan Rilis & Batasan Lingkungan (Release Readiness)

1. **Status Pengujian Unit Saat Ini:**
   - Flutter Unit & Smoke Tests: **284 / 284 LULUS (100%)**.
   - Cloud Functions Unit Tests: **104 / 104 LULUS (100%)**.
   - Static Analysis (`flutter analyze`): **0 issues found**.
2. **Lima Critical Blockers Rilis Produksi:**
   - **Blocker 1 (ENV Default)**: `lib/main.dart` default `ENV=development` yang mengaktifkan emulator host `10.0.2.2`. Wajib build dengan target produksi atau `--dart-define=ENV=production`.
   - **Blocker 2 (Manifest Internet)**: Izin `<uses-permission android:name="android.permission.INTERNET"/>` belum ada di `android/app/src/main/AndroidManifest.xml` (baru ada di debug).
   - **Blocker 3 (Deployment Backend)**: Cloud Functions, Firestore Rules, dan Cloud Storage bucket (`asia-southeast2`) belum dideploy ke project Firebase produksi resmi.
   - **Blocker 4 (App Check / Play Integrity)**: SHA-256 signing key rilis belum didaftarkan di Firebase App Check.
   - **Blocker 5 (Release Keystore)**: Belum ada `key.properties` dan keystore `.jks` resmi untuk penandatanganan APK produksi.
