# KONTRAK TEKS & LOCATOR E2E GUYUB.ID (E2E_TEXT_CONTRACT)

**Dokumen Pemetaan Locator Pengujian End-to-End Driver ke Layar UI**  
*Tanggal: 18 Oktober 2026*  
*Cabang: `fix-ui`*  

---

## 1. Pendahuluan & Prinsip Penyelarasan
Pengujian E2E pada repositori Guyub.id menggunakan mobile test driver (`@e2e-dev/mobile` & `e2e`) yang berinteraksi langsung dengan aplikasi Flutter melalui antarmuka aksesibilitas (*Android accessibility nodes*). Flutter `Key` internal **tidak diekspos** ke driver; driver menemukan widget berdasarkan:
- `screen.getByText(string | RegExp)`: Mencocokkan teks yang tampak atau label aksesibilitas (`Semantics(label: ...)`).
- `screen.getByPlaceholder(string)`: Mencocokkan `hintText` / placeholder pada input teks (`TextField`/`TextFormField`).

Aturan utama: **Dilarang memodifikasi berkas dalam `e2e/tests/`**. Semua rekonsiliasi dilakukan di lapisan presentasi Flutter tanpa merusak estetika desain bersih.

---

## 2. Inventaris Kontrak Per Berkas E2E

### 2.1 `e2e/tests/helper-consent.e2e.ts`
*Tujuan: Memastikan alur kesediaan relawan warga (AT-020 / INV-03) bersifat sukarela, eksplisit, dan tanpa tekanan.*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Saya Warga')` | `RoleSelectionScreen` | ✅ Cocok | Tampil pada kartu role warga. |
| `getByPlaceholder('Kode RT')` | `ResidentEntryScreen` | ⚠️ Mismatch Hint | `labelText: 'Kode RT'` ada, tapi `hintText` adalah `'Contoh: RT001JKT'`. Driver mencari placeholder `'Kode RT'`. Perlu `hintText: 'Kode RT'`. |
| `getByPlaceholder('Nama panggilan')` | `ResidentEntryScreen` | ⚠️ Mismatch Hint | `labelText: 'Nama panggilan'`, `hintText: 'Contoh: Budi'`. Perlu `hintText: 'Nama panggilan'`. |
| `getByText('Masuk ke RT')` | `ResidentEntryScreen` | ❌ Mismatch Teks | Tombol saat ini berlabel `'Gabung'`. Wajib diubah menjadi `'Masuk ke RT'`. |
| `getByText('Kesediaan Membantu')` | `ResidentSessionHomeScreen` & `AssistanceVolunteerScreen` | ✅ Cocok | Ada pada kartu navigasi dan judul AppBar. |
| `getByText(/Menjadi relawan sepenuhnya sukarela/)` | `AssistanceVolunteerScreen` | ✅ Cocok | Tampil pada teks penjelasan sukarela. |
| `getByText(/menolak setiap permintaan atau mengundurkan diri tanpa penalti/)` | `AssistanceVolunteerScreen` | ✅ Cocok | Tampil pada teks penjelasan tanpa denda. |
| `getByText(/RT hanya dapat mengirim permintaan setelah Anda setuju/)` | `AssistanceVolunteerScreen` | ✅ Cocok | Tampil pada syarat persetujuan RT. |
| `getByText(/Saya bersedia membantu secara sukarela/)` | `AssistanceVolunteerScreen` | ✅ Cocok | Label pada switch kesediaan relawan. |
| `getByText('Saya mengonfirmasi pilihan ini tanpa tekanan.')` | `AssistanceVolunteerScreen` | ✅ Cocok | Checkbox konfirmasi eksplisit sebelum simpan. |
| `getByText('Simpan kesediaan')` | `AssistanceVolunteerScreen` | ✅ Cocok | Tombol submit kesediaan relawan. |

---

### 2.2 `e2e/tests/offline-active-task.e2e.ts`
*Tujuan: Memastikan tugas aktif dan instruksi keselamatan tersinkron tetap terbaca saat offline (AT-006 / INV-06) dan penolakan tugas sukarela (INV-03).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Saya Warga')` | `RoleSelectionScreen` | ✅ Cocok | Kartu role warga. |
| `getByText('Lihat Tugas Kesiapsiagaan')` | `ResidentSessionHomeScreen` | ✅ Cocok | Tombol navigasi ke daftar tugas warga. |
| `getByPlaceholder('Kode RT')` | `ResidentEntryScreen` | ⚠️ Mismatch Hint | Perlu `hintText: 'Kode RT'`. |
| `getByPlaceholder('Nama panggilan')` | `ResidentEntryScreen` | ⚠️ Mismatch Hint | Perlu `hintText: 'Nama panggilan'`. |
| `getByText('Masuk ke RT')` | `ResidentEntryScreen` | ❌ Mismatch Teks | Tombol saat ini berlabel `'Gabung'`. Wajib diubah menjadi `'Masuk ke RT'`. |
| `getByText(new RegExp('Persiapan rumah tangga'))` | `ResidentTaskListScreen` | ✅ Cocok | Baris tugas template pada daftar tugas. |
| `getByText(new RegExp('Jangan mendekati air banjir atau instalasi listrik basah'))` | `ResidentTaskDetailScreen` | ✅ Cocok | Teks keselamatan terkunci. |
| `getByText(/Mode offline\. Sesi dan informasi tugas tersimpan belum diverifikasi ulang/)` | `ResidentSessionHomeScreen` | ✅ Cocok | Banner status sesi offline unverified. |
| `getByText(/Mode offline • data tugas tersimpan, belum diperbarui/)` | `ResidentTaskListScreen` | ✅ Cocok | Banner status tugas offline. |
| `getByText('Tidak Ikut')` | `ResidentTaskDetailScreen` | ✅ Cocok | Tombol penolakan partisipasi sukarela. |
| `getByText('Saya Ikut')` | `ResidentTaskDetailScreen` | ✅ Cocok | Tombol keikutsertaan sukarela. |
| `getByText(/Ikut atau tidak ikut adalah pilihan Anda/)` | `ResidentTaskDetailScreen` | ✅ Cocok | Teks edukasi sukarela tanpa paksaan. |
| `getByText('Keluar')` | `ResidentSessionHomeScreen` & Dialog | ✅ Cocok | Tooltip/tombol keluar dan tombol konfirmasi dialog `'Keluar'`. |
| `getByText('Keluar dari sesi ini?')` | `ResidentSessionHomeScreen` Dialog | ✅ Cocok | Judul dialog konfirmasi sign out warga. |

---

### 2.3 `e2e/tests/offline-emergency.e2e.ts`
*Tujuan: Memastikan rute darurat publik tanpa sesi dapat dibuka saat luring dan tidak mengarang direktori (AT-007 / INV-06 / INV-10).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Kesiapsiagaan banjir bersama warga')` | `RoleSelectionScreen` | ✅ Cocok | Subtitle aplikasi. |
| `getByText('Saya Ketua RT/RW atau Pendamping')` | `RoleSelectionScreen` | ✅ Cocok | Kartu role operator. |
| `getByText('Saya Warga')` | `RoleSelectionScreen` | ✅ Cocok | Kartu role warga. |
| `getByText('Darurat')` | `RoleSelectionScreen` | ❌ Mismatch Teks | Tombol saat ini berlabel `'Informasi Darurat'`. Wajib berlabel `'Darurat'` (atau Semantics `'Darurat'`). |
| `getByText('Informasi Darurat')` | `EmergencyDirectoryScreen` | ✅ Cocok | Judul AppBar layar direktori darurat. |
| `getByText('Mode offline • menampilkan direktori yang tersimpan di perangkat.')` | `EmergencyDirectoryScreen` | ✅ Cocok | Pesan kartu status offline. |
| `getByText(/Belum ada direktori darurat tersimpan.../)` | `EmergencyDirectoryScreen` | ❌ Mismatch Teks | Teks ini hilang di `_UnauthenticatedEmergencyView`. Wajib dicantumkan pesan bahwa direktori belum tersimpan di perangkat ini. |
| `getByText('Kontak Darurat')` (harus `toBeHidden()`) | `EmergencyDirectoryScreen` | ✅ Cocok | Bagian Kontak Darurat RT tidak muncul saat tanpa sesi dan tanpa cache. |

---

### 2.4 `e2e/tests/operator-flow.e2e.ts`
*Tujuan: Memastikan alur login operator RT, membuka katalog aman, membuat draf, dan konfirmasi aktivasi (AT-001 / AT-002 / AT-003 / AT-016).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Saya Ketua RT/RW atau Pendamping')` | `RoleSelectionScreen` | ✅ Cocok | Kartu masuk operator. |
| `getByPlaceholder('Email')` | `OperatorLoginScreen` | ⚠️ Mismatch Hint | `labelText: 'Email'`, `hintText: 'nama@example.com'`. Perlu `hintText: 'Email'`. |
| `getByPlaceholder('Kata sandi')` | `OperatorLoginScreen` | ⚠️ Mismatch Hint | `labelText: 'Kata sandi'`, tidak ada `hintText`. Perlu `hintText: 'Kata sandi'`. |
| `getByText('Masuk')` | `OperatorLoginScreen` | ✅ Cocok | Tombol submit login operator. |
| `getByText('Ruang Operator')` | `OperatorHomeScreen` | ✅ Cocok | Judul AppBar pada tab Beranda operator. |
| `getByText('Ketua RT/RW')` | `OperatorHomeScreen` | ✅ Cocok | Chip peran operator pada hero header. |
| `getByText('RT ' + RT_ID)` | `OperatorHomeScreen` | ❌ Mismatch Teks | Hero header saat ini hanya menampilkan nama komunitas (misal "Komunitas rt-e2e"). Wajib menyertakan chip sekunder `"RT <rtId>"`. |
| `getByText('Buka Katalog Tugas Aman')` | `OperatorHomeScreen` | ✅ Cocok | Tombol aksi cepat katalog tugas. |
| `getByText('Katalog Tugas Aman')` | `TaskCatalogScreen` | ✅ Cocok | Judul AppBar katalog tugas. |
| `getByText(new RegExp('Persiapan rumah tangga'))` | `TaskCatalogScreen` & `TaskDraftScreen` | ✅ Cocok | Judul template tugas. |
| `getByText(new RegExp('Jangan mendekati air banjir...'))` | `TaskCatalogScreen` & `TaskDraftScreen` | ✅ Cocok | Instruksi keselamatan terkunci. |
| `getByText('Pilih template')` | `TaskCatalogScreen` | ✅ Cocok | Tombol memilih template untuk draf. |
| `getByText('Siapkan Draf Tugas')` | `TaskDraftScreen` | ✅ Cocok | Judul AppBar layar draf tugas. |
| `getByText(/Instruksi template terkunci/)` | `TaskDraftScreen` | ✅ Cocok | Judul kartu instruksi terkunci. |
| `getByText(/Simpan dokumen penting.../)` | `TaskDraftScreen` | ✅ Cocok | Instruksi inti template terkunci. |
| `getByText(/KESELAMATAN/)` | `TaskDraftScreen` | ✅ Cocok | Label penanda instruksi keselamatan. |
| `getByText('Bagian yang dapat diatur')` | `TaskDraftScreen` | ✅ Cocok | Judul bagian form slot aman operator. |
| `getByText('Pilih batas waktu')` | `TaskDraftScreen` | ✅ Cocok | Tombol pemilih tanggal/jam batas waktu. |
| `getByText('Jenis lokasi umum (opsional)')` | `TaskDraftScreen` | ✅ Cocok | Label dropdown jenis lokasi umum. |
| `getByText('Lanjut ke konfirmasi')` | `TaskDraftScreen` | ✅ Cocok | Tombol submit pembuatan draf tugas. |
| `getByText('Pilih batas waktu di masa depan.')` | `TaskDraftScreen` | ✅ Cocok | Pesan validasi jika batas waktu belum diisi. |
| `getByText('Konfirmasi Aktivasi Tugas')` | `TaskCampaignConfirmationScreen` | ✅ Cocok | Judul AppBar konfirmasi aktivasi. |
| `getByText('Draf belum aktif dan belum dibagikan.')` | `TaskCampaignConfirmationScreen` | ✅ Cocok | Banner edukasi status draf belum aktif. |
| `getByText('Salin teks untuk WhatsApp')` | `TaskCampaignConfirmationScreen` & `TaskActiveCampaignsScreen` | ✅ Cocok | Tombol salin WhatsApp (hanya aktif setelah aktivasi). |
| `getByText('Konfirmasi dan aktifkan')` | `TaskCampaignConfirmationScreen` | ✅ Cocok | Tombol aktivasi tugas terkonfirmasi. |
| `getByText('Tugas aktif untuk RT ini.')` | `TaskCampaignConfirmationScreen` | ✅ Cocok | Banner status setelah tugas berhasil aktif. |

---

### 2.5 `e2e/tests/resident-proposal.e2e.ts`
*Tujuan: Memastikan usulan warga bersifat inert (tidak otomatis aktif) dan hanya menjadi konteks tinjauan operator (AT-012 / INV-08).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Usulkan Persiapan Warga')` | `ResidentSessionHomeScreen` & `ResidentProposalScreen` | ✅ Cocok | Kartu beranda warga & judul AppBar usulan. |
| `getByPlaceholder('Judul usulan')` | `ResidentProposalScreen` | ⚠️ Mismatch Hint | `labelText: 'Judul usulan'`, tidak ada `hintText`. Perlu `hintText: 'Judul usulan'`. |
| `getByPlaceholder('Penjelasan singkat')` | `ResidentProposalScreen` | ⚠️ Mismatch Hint | `labelText: 'Penjelasan singkat'`, tidak ada `hintText`. Perlu `hintText: 'Penjelasan singkat'`. |
| `getByText('Kirim usulan ke RT')` | `ResidentProposalScreen` | ✅ Cocok | Tombol kirim usulan warga. |
| `getByText(/Menunggu Tinjauan RT/)` | `ResidentProposalScreen` | ✅ Cocok | Status kartu konfirmasi pengiriman usulan. |
| `getByText(/Usulan ini belum menjadi tugas\. Tidak ada tugas yang diaktifkan atau dikirim\./)` | `ResidentProposalScreen` | ✅ Cocok | Banner edukasi bahwa usulan bukan tugas aktif. |
| `getByText(/Usulan: Periksa saluran air bersama/)` | `ResidentProposalScreen` | ✅ Cocok | Rincian judul usulan yang dikirim. |
| `getByText('Tinjau Usulan Warga')` | `OperatorHomeScreen` & `ResidentProposalReviewScreen` | ✅ Cocok | Tombol aksi cepat operator & judul AppBar. |
| `getByText(/Dari: Sari/)` | `ResidentProposalReviewScreen` | ✅ Cocok | Atribusi nama panggilan pengusul. |
| `getByText(/Kategori: Persiapan rumah tangga/)` | `ResidentProposalReviewScreen` | ✅ Cocok | Label kategori usulan warga. |
| `getByText('Pilih template aman untuk draf')` | `ResidentProposalReviewScreen` | ✅ Cocok | Tombol pemetaan usulan ke draf template aman. |
| `getByText('Arahkan ke kanal resmi')` | `ResidentProposalReviewScreen` | ✅ Cocok | Tombol eskalasi usulan ke kanal resmi. |
| `getByText('Tutup usulan')` | `ResidentProposalReviewScreen` | ✅ Cocok | Tombol penutupan/penolakan usulan warga. |

---

### 2.6 `e2e/tests/rt-history.e2e.ts`
*Tujuan: Memastikan riwayat kesiapsiagaan dimiliki RT, timeline event server-authoritative, dan penutupan tugas terpisah dari verifikasi (AT-015).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Lihat Riwayat Tugas RT')` | `OperatorHomeScreen` | ✅ Cocok | Aksi cepat menuju riwayat tugas RT. |
| `getByText('Riwayat Tugas RT')` | `TaskHistoryScreen` | ✅ Cocok | Judul AppBar riwayat tugas. |
| `getByText(new RegExp('Persiapan rumah tangga'))` | `TaskHistoryScreen` | ✅ Cocok | Judul tugas historis. |
| `getByText(/Status: Aktif/)` | `TaskHistoryScreen` | ✅ Cocok | Baris status tugas aktif. |
| `getByText(/Versi template: 1/)` | `TaskHistoryScreen` | ✅ Cocok | Versi snapshot template tugas. |
| `getByText('Back')` | AppBar BackButton | ⚠️ Verifikasi Driver | Tombol Back default Flutter di Android. Perlu dipastikan memiliki Semantics/tooltip `'Back'`. |
| `getByText('Tinjau Tugas Aktif')` | `OperatorHomeScreen` | ✅ Cocok | Aksi cepat menuju daftar tugas aktif RT. |
| `getByText('Tugas Aktif RT')` | `TaskActiveCampaignsScreen` | ✅ Cocok | Judul AppBar tugas aktif operator. |
| `getByText('Tutup tugas aktif')` | `TaskActiveCampaignsScreen` | ✅ Cocok | Tombol penutupan tugas aktif operator. |
| `getByText('Tutup tugas aktif?')` | `TaskActiveCampaignsScreen` Dialog | ✅ Cocok | Judul dialog konfirmasi penutupan tugas. |
| `getByText('Tutup tugas')` | `TaskActiveCampaignsScreen` Dialog | ✅ Cocok | Tombol konfirmasi tutup tugas pada dialog. |
| `getByText(/Status: Ditutup/)` | `TaskHistoryScreen` | ✅ Cocok | Baris status tugas yang telah ditutup. |
| `getByText('Lihat riwayat perubahan')` | `TaskHistoryScreen` | ✅ Cocok | Tombol membuka riwayat timeline event. |
| `getByText('Perubahan yang dicatat server:')` | `TaskHistoryScreen` | ✅ Cocok | Judul daftar event audit server. |
| `getByText(/^Diaktifkan: /)` | `TaskHistoryScreen` | ✅ Cocok | Baris event aktivasi tugas. |
| `getByText(/^Ditutup: /)` | `TaskHistoryScreen` | ✅ Cocok | Baris event penutupan tugas. |

---

### 2.7 `e2e/tests/task-cycle.e2e.ts`
*Tujuan: Memastikan siklus lengkap pengerjaan warga tetap "Menunggu Verifikasi RT" hingga diverifikasi operator (AT-005 / INV-09).*

| Locator / String E2E | Layar UI Pemilik | Status Saat Ini | Tindakan / Rekonsiliasi |
|:---|:---|:---|:---|
| `getByText('Saya Ikut')` | `ResidentTaskDetailScreen` | ✅ Cocok | Tombol keikutsertaan warga. |
| `getByText('Kirim untuk Verifikasi RT')` | `ResidentTaskDetailScreen` | ✅ Cocok | Tombol submit catatan pengerjaan warga. |
| `getByText(/Menunggu Verifikasi RT/)` | `ResidentTaskDetailScreen` | ✅ Cocok | Status pengerjaan belum diverifikasi. |
| `getByText('Tinjau Penyelesaian Warga')` | `OperatorHomeScreen` | ✅ Cocok | Aksi cepat antrean verifikasi operator. |
| `getByText('Verifikasi Tugas')` | `TaskVerificationQueueScreen` | ✅ Cocok | Judul AppBar antrean verifikasi penyelesaian. |
| `getByText(/Dikirim oleh Sari/)` | `TaskVerificationQueueScreen` | ✅ Cocok | Atribusi warga yang menyelesaikan. |
| `getByText(/Status: Menunggu Verifikasi RT/)` | `TaskVerificationQueueScreen` | ✅ Cocok | Status verifikasi item antrean. |
| `getByText('Tinjau dan Verifikasi')` | `TaskVerificationQueueScreen` | ✅ Cocok | Tombol membuka verifikasi item. |
| `getByText('Verifikasi penyelesaian?')` | `TaskVerificationQueueScreen` Dialog | ✅ Cocok | Judul dialog konfirmasi verifikasi. |
| `getByText('Verifikasi')` | `TaskVerificationQueueScreen` Dialog | ✅ Cocok | Tombol aksi konfirmasi verifikasi pengerjaan. |
| `getByText(/Belum ada penyelesaian yang menunggu verifikasi RT/)` | `TaskVerificationQueueScreen` | ✅ Cocok | Pesan kosong saat antrean habis. |

---

## 3. Daftar Defisit Mismatch yang Wajib Diperbaiki di Bagian 1

1. **`RoleSelectionScreen`**:
   - Tombol `'Informasi Darurat'` wajib berlabel `'Darurat'` (atau `Semantics(label: 'Darurat')`).
2. **`ResidentEntryScreen`**:
   - Tombol `'Gabung'` wajib diubah menjadi `'Masuk ke RT'`.
   - Field `TextFormField` Kode RT wajib menambahkan `hintText: 'Kode RT'`.
   - Field `TextFormField` Nama panggilan wajib menambahkan `hintText: 'Nama panggilan'`.
3. **`OperatorLoginScreen`**:
   - Field Email wajib menambahkan `hintText: 'Email'`.
   - Field Kata sandi wajib menambahkan `hintText: 'Kata sandi'`.
4. **`ResidentProposalScreen`**:
   - Field Judul usulan wajib menambahkan `hintText: 'Judul usulan'`.
   - Field Penjelasan singkat wajib menambahkan `hintText: 'Penjelasan singkat'`.
5. **`OperatorHomeScreen`**:
   - Hero header wajib tetap menampilkan chip / teks sekunder `'RT <communityId>'` (misal `RT rt-e2e`) agar `getByText('RT ' + RT_ID)` lolos, di samping nama komunitas utama.
6. **`EmergencyDirectoryScreen`**:
   - Pada `_UnauthenticatedEmergencyView`, wajib mencantumkan pesan baku: `'Belum ada direktori darurat tersimpan di perangkat ini.'` agar regex `/Belum ada direktori darurat tersimpan.../` terpenuhi saat offline tanpa cache.
   - Sesuai Keputusan Pengguna 1b.(ii): Nomor darurat nasional di bawah judul tersendiri `"Nomor darurat nasional"`, tanpa pernah memakai judul `"Kontak Darurat"`.
7. **`BackButton` Navigation**:
   - Pastikan tombol kembali di AppBar memiliki `tooltip: 'Back'` agar `getByText('Back')` di `rt-history.e2e.ts` dapat menemukannya.
