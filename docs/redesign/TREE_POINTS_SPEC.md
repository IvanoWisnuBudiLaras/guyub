# Spesifikasi Fitur "Pohon Guyub" (Tree Points Specification)

> **Status Dokumen**: SPESIFIKASI ARSITEKTUR & DESAIN SAJA (Gatekeeper: Belum ada kode implementasi, belum ada dependensi baru yang diinstal, dan belum menyentuh backend).
> **Tanggal**: 18 Oktober 2026
> **Penulis**: AI Assistant (Antigravity) & Tim Pengembang Guyub.id

---

## 5a. Kecocokan Produk & Hasil Temuan Proposal MAGE

### 1. Temuan Bagian 0b (Proposal MAGE vs Kondisi Eksisting)
Berdasarkan ekstraksi mendalam berkas proposal asli `docs/MAGE 12_Tahap 1_AppDev_Tim Tidak Tau Diri.docx`:
- **Hasil Pencarian Kata Kunci**: Kata kunci seperti `pohon`, `tree`, `penghijauan`, `kepemilikan`, `vegetasi`, `biopori`, maupun `resapan` **tidak ditemukan** dalam teks proposal MAGE. Fitur ini merupakan inisiatif baru dari product owner untuk memperkuat pilar mitigasi preventif jangka panjang berbasis warga.
- **Peta Titik Kumpul vs Titik Pohon**: Proposal MAGE hanya menyebutkan konsep peta evakuasi dan titik kumpul darurat (`assembly points`). Namun pada audit arsitektur sebelumnya (`AUDIT_AND_PLAN.md` Langkah 5 & Batch 5), ditemukan bahwa `emergency_directories` di backend saat ini sengaja **tidak mengekspos koordinat latitude/longitude**, melainkan deskripsi lokasi tekstual (mis. `"Balai RW 05"`) untuk menghindari kebocoran PII dan menjaga kesederhanaan MVP.
- **Definisi Baru Product Owner**: Fitur kepemilikan pohon warga diresmikan sebagai bagian dari misi Guyub.id: RT membuka kampanye tugas penghijauan aman, warga berpartisipasi menanam pohon, mendokumentasikan melalui in-app camera anti-pemalsuan, dan titik pohon terverifikasi ditampilkan di peta RT sebagai aset resapan dan penghijauan komunitas.

### 2. Keterkaitan dengan Pencegahan Banjir (Flood Mitigation)
Penghijauan lingkungan RT bukan sekadar kosmetik visual, melainkan komponen struktural hidrologis:
- **Peningkatan Kapasitas Infiltrasi Air Tanah**: Vegetasi berakar dalam mempercepat penyerapan air hujan ke lapisan akuifer dangkal, menurunkan koefisien limpasan air permukaan (*runoff coefficient* $C$), sehingga memperlambat waktu konsentrasi air hujan menuju saluran drainase mikro RT.
- **Mitigasi Erosi & Sedimentasi**: Erosi tanah di pekarangan dan sempadan menyumbang sedimentasi lumpur yang mendangkalkan parit dan drainase RT. Penanaman pohon menjaga stabilitas agregat tanah.
- **Konteks Guyub**: Mengubah kesiapsiagaan dari sekadar "reaktif menunggu BMKG" menjadi "aksi gotong royong terukur sepanjang tahun".

---

## 5b. Analisis Benturan Invarian Arsitektur & Rekomendasi Resolusi

| Invarian PRD | Bunyi / Batasan | Benturan Potensial | Opsi Resolusi & Rekomendasi |
| :--- | :--- | :--- | :--- |
| **INV-05 (No Forbidden Personal Data)** | Dilarang menyimpan NIK, alamat lengkap, atau koordinat GPS presisi warga. Detektor `precise_coordinate_detector.ts` memblokir teks yang mengandung format lat/lng. | Menyimpan titik pohon dengan koordinat GPS presisi di pekarangan warga secara de facto mengekspos lokasi rumah warga pemilik pohon tersebut. | **Rekomendasi (Opsi A pada 5c)**: Titik publik di peta RT diagregasi ke grid kasar (h3 cell atau snap ke grid ~100–200m). Koordinat GPS presisi hanya disimpan terisolasi dan hanya dapat diakses oleh RT dan warga pemilik untuk verifikasi lapangan. Detektor teks tetap aktif untuk field teks bebas. |
| **INV-07 (Photo Evidence Transient & Sanitized)** | Foto bukti bersifat opsional, metadata lokasi (EXIF GPS) wajib dibuang sebelum penyimpanan, dan file fisik dihapus permanen setelah 30 hari. | Titik pohon membutuhkan persistensi permanen (pohon bertumbuh tahunan), sementara foto bukti awal harus dibersihkan setelah 30 hari. Selain itu, pengambilan foto membutuhkan kepastian lokasi. | **Rekomendasi**: Pisahkan *lifecycle* foto bukti dan metadata titik pohon. Foto bukti tanaman mengikuti aturan retensi 30 hari (dihapus dari Storage), namun record `TreePointRecord` (status verifikasi, waktu tanam, jenis pohon, koordinat kasar) disimpan permanen di Firestore sebagai aset RT. EXIF tetap di-strip di client sebelum upload; koordinat diperoleh via GPS API perangkat saat foto diambil. |
| **INV-03 (Voluntary Participation & Anti-Coercion)** | Partisipasi sukarela, tanpa ranking, shaming, denda, kuota paksa, atau leaderboard kompetitif. | Risiko gamifikasi jumlah pohon: leaderboard "warga dengan pohon terbanyak" memicu tekanan sosial / kompetisi tidak sehat. | **Rekomendasi**: Tidak ada leaderboard peringkat individu warga. Metrik hanya diagregasikan di level komunitas RT: "Total X pohon tertanam di RT 03" sebagai pencapaian gotong royong bersama. |
| **INV-04 (No Hazardous Tasks)** | Larangan tugas berbahaya: dilarang masuk saluran air, mendekati arus deras, atau pekerjaan darurat profesional. | Menanam pohon di tanggul sungai liar, tebing curam, atau di dekat jaringan kabel listrik tegangan tinggi berbahaya bagi warga. | **Rekomendasi**: Template tugas penghijauan dikunci instruksi keselamatannya: hanya diizinkan di pekarangan rumah warga atau lahan fasum aman yang ditunjuk RT. Dilarang menanam di sempadan sungai berarus deras tanpa izin dinas lingkungan. |
| **INV-09 (RT Verification Gate)** | Pengajuan warga bukan penyelesaian resmi hingga diverifikasi oleh operator RT berwenang. | Titik pohon tidak boleh langsung muncul di peta publik begitu warga mengunggah foto. | **Rekomendasi**: Alur state mesin: `PENDING_RT_VERIFICATION` -> `VERIFIED` -> tampil di peta publik. Jika RT menolak (`REJECTED`), titik tidak ditampilkan di peta RT. |
| **INV-10 (Official Escalation Remains Official)** | Urusan di luar kapasitas warga dialihkan ke kanal resmi pemerintah/kedaruratan. | Penanaman pohon di ruang terbuka hijau kota (RTH skala besar) atau penebangan/perapian pohon liar di jalan raya umum adalah wewenang Sudin Pertamanan/DLH. | **Rekomendasi**: Sertakan disclaimer pada template: jika warga melihat pohon tumbang atau membutuhkan bibit skala besar, gunakan kanal resmi pemerintah (mis. JAKI / Dinas Pertamanan). |
| **INV-06 (Offline Reliability)** | Konten aktif tetap terbaca offline. Cache lokal tidak boleh macet saat koneksi terputus. | Peta tile interaktif (OSM/Google Maps) gagal memuat gambar peta saat tidak ada koneksi internet. | **Rekomendasi**: Fallback graceful: saat offline, layar menampilkan fallback berupa daftar kartu titik pohon (*list view*) berbasis cache lokal, bukan layar kosong atau crash. Peta menampilkan status offline banner. |

---

## 5c. Analisis Opsi Privasi Koordinat Lokasi

Ketika warga memotret pohon di pekarangan rumahnya, koordinat presisi ($< 5\text{ m}$) berpotensi menjadi *de-anonymization proxy* bagi warga anonim:

| Model Opsi | Mekanisme | Kelebihan | Risiko & Trade-off | Rekomendasi |
| :--- | :--- | :--- | :--- | :--- |
| **Opsi A: Dual-Resolution (Privasi Adaptif)** | - Koordinat presisi (lat, lng $\pm 5\text{ m}$) disimpan di sub-koleksi privat, hanya bisa dibaca RT & pemilik.<br>- Titik publik untuk warga satu RT disamarkan (dibulatkan ke grid sel $\approx 100\text{–}200\text{ m}$ atau centroid RT). | - Mematuhi prinsip INV-05.<br>- Pekarangan pribadi tidak terlacak oleh publik.<br>- RT tetap bisa survei fisik langsung ke lokasi. | Butuh komputasi pembulatan sel di Cloud Functions saat verifikasi titik. | **SANGAT DIREKOMENDASIKAN** |
| **Opsi B: Presisi Terbuka untuk Seluruh RT** | Koordinat presisi ditampilkan pada pin peta untuk semua warga yang tergabung dalam RT tersebut. | Tampilan peta sangat akurat pin-point. | Pelanggaran langsung terhadap INV-05. Rumah warga rentan/anonim terpetakan secara presisi di peta aplikasi. | **DITOLAK (Risiko Privasi Tinggi)** |
| **Opsi C: Hanya Fasum / Lahan Publik RT** | Pohon hanya boleh ditanam di titik fasilitas umum (fasum/fasos) yang telah didaftarkan RT sebelumnya. | Nol risiko privasi rumah warga. | Partisipasi warga terbatas karena tidak semua RT memiliki lahan fasum luas; mayoritas menanam di tabulampot/pekarangan. | Dapat dijadikan opsi tambahan di masa depan, tapi membatasi adopsi. |

### Persetujuan & Hak Hapus Data
1. **Consent Eksplisit**: Sebelum membuka kamera dan mengakses lokasi GPS, warga disajikan lembar persetujuan (*Consent Sheet*): *"Lokasi perkiraan pohon akan dibagikan ke peta lingkungan RT Anda untuk pemantauan penghijauan."*
2. **Hak Hapus Data (Right to be Forgotten)**:
   Integrasi dengan callable `deleteOwnResidentData`:
   - Jika warga meminta penghapusan datanya, seluruh foto bukti miliknya dihapus dari Storage.
   - Pilihan kebijakan data pohon: Record titik pohon dianonimkan (dilepaskan dari `residentId`/`nickname`, menjadi `"Pohon Warga (Anonim)"`) agar agregat penghijauan RT tidak hilang, atau dihapus secara penuh sesuai preferensi RT.

---

## 5d. Mekanisme Anti-Pemalsuan yang Jujur & Realistis

Menghindari klaim berlebihan ("100% anti-fraud"), berikut kontrol keamanan berlapis yang dapat diterapkan:

```
[ Pengambilan Foto In-App ]
         │
         ├── Tanpa Akses Galeri (Strict Camera Source)
         ├── Timestamp Server-Authoritative (Server vs Device Clock Delta)
         ├── Validasi Lokasi (Accuracy <= 30m, Mock Location Detection)
         ├── App Check / Play Integrity (Attestation Token)
         ▼
[ Cloud Functions Ingestion ]
         │
         ├── Geofencing Area RT (Batas radius / polygon RT)
         ├── Deteksi Duplikasi Spatio-Temporal (Jarak < 3m dalam interval < 5 menit)
         ├── Rate Limiting (Maks X pengajuan per sesi per hari)
         ▼
[ Antrean Verifikasi RT ]
         │
         ├── Operator RT memeriksa foto & kesesuaian fisik
         ▼
[ Terverifikasi di Peta RT ]
```

### 1. Kontrol Teknis yang Dapat Dijamin
- **In-App Camera Capture Only**: Menggunakan `ImageSource.camera` secara eksklusif; menonaktifkan pemilih galeri file.
- **Server-Authoritative Timestamp**: Waktu pencatatan resmi adalah `request.time` dari Firebase Server, bukan waktu jam di perangkat client (mencegah manipulasi jam HP). Delta waktu client-server dianalisis jika melebihi ambang batas toleransi ($> 5\text{ menit}$).
- **Lokasi Palsu (Mock Location / Fake GPS Detection)**: Pustaka lokasi membaca flag `isMocked` dari Android Location API. Pengajuan dengan `isMocked == true` langsung ditolak di client dan divalidasi ulang di backend.
- **Akurasi Minimum GPS**: Hanya menerima koordinat dengan akurasi horizontal $\le 30\text{ meter}$.
- **Geofence Wilayah RT**: Backend memvalidasi koordinat berada di dalam bounding box / radius toleransi RT bersangkutan.
- **Rate Limiting & Duplikasi**: Menolak pengajuan titik baru jika koordinatnya berjarak $< 3\text{ meter}$ dari titik pohon lain yang diajukan dalam kurun waktu singkat.
- **Gerbang Manusia (RT Verification Gate)**: Tidak ada titik yang muncul di peta umum tanpa persetujuan ketua RT/pendamping yang mengenal wilayahnya secara langsung.

### 2. Batasan Kejujuran (Yang TIDAK Bisa Dijamin 100%)
- *Re-photography*: Foto terhadap layar monitor atau foto fisik pohon lain tidak dapat dideteksi 100% tanpa model AI computer-vision khusus (dan AI pun dapat dikelabui).
- *Hardware Hooking/Root*: Perangkat yang di-root dengan modul KernelSU/Xposed tingkat rendah dapat memalsukan kamera virtual di level OS.
- *Kelangsungan Hidup Tanaman*: Foto saat tanam tidak menjamin bibit disiram atau hidup 6 bulan kemudian tanpa program verifikasi berkala (*check-in tumbuh*).

---

## 5e. Model Data Usulan & Spesifikasi Backend

### 1. Kategori Template Baru di Safe Catalog
Tambahkan kategori terkunci:
- Enum ID: `GREENING` / `PENJAHIJUAN`
- Judul Template Contoh: *"Penanaman Pohon Resapan Pekarangan / Fasum"*
- Estimasi Durasi: 30 menit
- Instruksi Inti (Terkunci): Menyiapkan lubang tanam minimal kedalaman 30–50 cm, menanam bibit pohon pelindung/buah, menyiram air secukupnya.
- Instruksi Keselamatan (Terkunci): Pastikan lokasi tanam aman dari pipa gas/air bawah tanah, tidak menanam di sempadan curam yang mudah longsor, gunakan sarung tangan kerja, dan dilarang menanam di bawah jalur kabel listrik tegangan tinggi.

### 2. Struktur Koleksi Firestore Usulan

#### Koleksi Utama: `tree_points`
Path: `/communities/{communityId}/tree_points/{treePointId}`
```typescript
interface TreePointDocument {
  treePointId: string;
  communityId: string;
  taskId: string;                      // Relasi ke kampanye tugas RT
  residentId: string;                  // Opaque ID warga (bukan NIK)
  submitterNickname: string;           // Nama panggilan (mis. "Pak Budi")
  speciesHint?: string;                // Jenis pohon (mis. "Mangga", "Ketapang Kencana")
  plantedAtServer: Timestamp;          // Waktu server (authoritative)
  clientReportedAt: Timestamp;         // Waktu klaim perangkat
  status: 'PENDING_RT_VERIFICATION' | 'VERIFIED' | 'REJECTED';
  rejectionReason?: string;
  verifiedBy?: string;                 // UID Operator RT
  verifiedAt?: Timestamp;
  
  // Koordinat Kasar (Aman untuk dibaca seluruh warga satu RT)
  coarseLocation: {
    cellId: string;                    // Geohash tingkat 6 (~1.2 km x 600 m) atau sel 150m
    approximateLat: number;
    approximateLng: number;
  };
  
  // Sub-koleksi privat: /tree_points/{treePointId}/private/location
  // Hanya bisa dibaca oleh RT dan residentId pembuat:
  // {
  //   exactLat: number,
  //   exactLng: number,
  //   accuracyMeters: number,
  //   isMocked: boolean
  // }

  evidenceStoragePath?: string;        // Path gambar di Cloud Storage (retensi 30 hari)
  evidenceExpiresAt?: Timestamp;       // TTL untuk cleanup worker
}
```

### 3. Callable Cloud Functions yang Dibutuhkan
1. `submitTreePoint`: Menerima lat/lng, akurasi, flag mock, foto bukti base64/upload ID, jenis pohon, dan taskId. Melakukan sanitasi koordinat kasar dan menyimpan dokumen dengan status `PENDING_RT_VERIFICATION`.
2. `listCommunityTreeMap`: Mengembalikan daftar titik pohon dengan status `VERIFIED` berkoordinat kasar untuk ditampilkan pada peta warga.
3. `verifyTreePoint`: Operator RT menyetujui atau menolak titik pohon, mengisi catatan atau alasan penolakan.
4. `deleteTreePoint`: Pemilik pohon atau RT menghapus record jika pohon mati atau data dicabut.

### 4. Firestore & Storage Security Rules
- Warga dalam RT hanya diizinkan membaca (`get`, `list`) dokumen `tree_points` dengan status `VERIFIED` dan field `coarseLocation`.
- Sub-koleksi `private/location` hanya diizinkan dibaca jika `request.auth.token.role == 'operator'` atau `request.auth.uid == resource.data.residentId`.
- Storage Bucket: Bukti foto pohon diletakkan di `/communities/{communityId}/trees/{treePointId}.jpg` dengan metadata strip enforced dan private read only.

### 5. Dampak ke `precise_coordinate_detector.ts`
Backend validator saat ini mendeteksi pola lat/lng di field teks bebas (seperti `completionNote` atau `proposalDescription`).
- **Penyesuaian**: Koordinat GPS pohon harus dikirimkan melalui **field terstruktur bertipe numerik** (`exactLat`, `exactLng` berformat Float), bukan string teks bebas. Dengan demikian, `precise_coordinate_detector.ts` tetap menjaga field teks bebas dari kebocoran alamat, sementara field terstruktur divalidasi oleh skema tipe data dan aturan otorisasi tersendiri.

### 6. Koordinat Publik Titik Kumpul (Integrasi Batch 5 Audit)
Sebagai opsi terpisah dalam spesifikasi ini: Direktori darurat (`emergency_directories`) dapat ditambahkan field opsional `coarseLocation` untuk titik kumpul evakuasi resmi RT (misalnya lapangan RW atau balai warga). Berbeda dengan pohon pribadi, titik kumpul fasum bersifat publik sehingga dapat ditampilkan sebagai pin khusus pada layer peta yang sama.

---

## 5f. Rencana Implementasi Flutter & Pilihan Paket Peta

### 1. Izin & Alur Pengguna (User Flow)
1. **Layar Detail Tugas**: Jika kategori tugas adalah `GREENING`, tombol aksi berubah menjadi *"Tanam & Dokumentasikan Pohon"*.
2. **Izin Perangkat**: Permintaan izin runtime `CAMERA` dan `ACCESS_FINE_LOCATION` didahului layar edukasi privasi (*Rationale Sheet*).
3. **Layar Tangkap Foto Khusus**: Menampilkan kamera in-app, indikator status GPS (Hijau jika akurasi $\le 30\text{m}$, Kuning jika sedang mencari satelit), dan tombol shutter.
4. **Pratinjau & Pengiriman**: Menampilkan foto, perkiraan sel lokasi di peta mini, dan input opsional jenis pohon.
5. **Tab / Layar Peta Komunitas**: Tab baru *"Peta Pohon RT"* di ruang warga dan operator, menampilkan layer titik pohon dan statistik gotong royong.

### 2. Perbandingan Paket Peta untuk Android

| Paket | Kelebihan | Kekurangan / Trade-off | Rekomendasi |
| :--- | :--- | :--- | :--- |
| **flutter_map (OpenStreetMap/Vector)** | - Pure Flutter widget, performa render tinggi.<br>- Ringan, tanpa API key Google Play Console.<br>- Sangat fleksibel untuk styling custom marker dan offline tile caching. | Tile server gratisan OSM standard (`tile.openstreetmap.org`) dilarang untuk aplikasi produksi massal (kebijakan *Tile Usage Policy* OSM). Butuh penyedia tile resmi (mis. MapTiler / Stadia / self-hosted tile proxy). | **PILIHAN TERBAIK JANGKA PANJANG (dengan Tile Provider Terkelola)** |
| **MapLibre Native (maplibre_gl)** | - Render peta vektor GPU native mbtiles.<br>- Dukungan offline peta lokal tanpa internet sangat kuat. | Setup platform native Android/NDK lebih kompleks; bobot biner APK bertambah 15–20 MB. | Alternatif jika offline peta vektor mutlak diperlukan. |
| **google_maps_flutter** | - Standard industri Android, tile Google resmi.<br>- Dukungan satelit dan jalan akurat di Indonesia. | - Memerlukan Google Cloud Console API Key dengan billing aktif.<br>- Cache offline sangat terbatas dan melanggar ToS Google jika di-cache secara manual.<br>- Dependensi berat pada Google Play Services. | Kurang cocok untuk prinsip offline-critical Guyub.id. |

### 3. Kebijakan Tile & Penanganan Offline
- **Atribusi Wajib**: Wajib menampilkan atribusi `© OpenStreetMap contributors` di sudut bawah peta.
- **Fallback Offline Graceful**: Jika perangkat berada di mode offline (tanpa sinyal), aplikasi menampilkan banner: *"Peta interaktif offline. Menampilkan daftar titik pohon tersimpan."* disertai tampilan daftar kartu titik pohon (*ListView*) dari cache SQLite/SharedPreferences.

---

## 5g. Rencana Tahapan Bertahap (Roadmap T1–T6)

Pemisahan tegas antara pekerjaan backend (tim backend) dan pekerjaan UI (Flutter):

| Tahap | Fokus & Cakupan | File / Artefak Terkait | Dependensi | Risiko & Mitigasi | Estimasi | Tim |
| :---: | :--- | :--- | :--- | :--- | :---: | :---: |
| **T1** | **Kontrak & Skema Backend** | `docs/contracts/tree_point_contract.md`, definisi skema TypeScript | Persetujuan PO atas 5c & 5h | Perubahan skema di tengah jalan. Mitigasi: freeze spesifikasi di T1. | **S** | Tim Backend |
| **T2** | **Implementasi Backend & Emulator Tests** | `functions/src/tree_points/`, `firestore.rules`, emulator tests | T1 selesai | Rule bypass / kebocoran koordinat presisi. Mitigasi: unit test rules deny-by-default. | **M** | Tim Backend |
| **T3** | **UI In-App Camera & Submission Flow** | `lib/features/trees/presentation/`, boundary adapter client | T2 emulator ready | Izin kamera ditolak warga. Mitigasi: graceful fallback edukasi izin. | **M** | Flutter |
| **T4** | **Peta Komunitas & Visualisasi Titik** | Layar Peta RT, integrasi flutter_map / provider tile | T3 selesai | Tile server rate-limit. Mitigasi: disk caching & fallback list view. | **L** | Flutter |
| **T5** | **Alur Verifikasi RT & Rekap** | `TreeVerificationScreen`, tab status verifikasi di ruang operator | T2 & T4 | Operator kesulitan verifikasi. Mitigasi: tampilkan foto + sel jarak RT. | **M** | Flutter |
| **T6** | **E2E Tests, Sanitasi & Dokumentasi Rilis** | `e2e/tests/tree-points.e2e.ts`, update PRD & panduan pengguna | T1–T5 selesai | Regresi performa build APK. Mitigasi: jalankan unified gate. | **S** | Gabungan |

---

## 5h. 10 Pertanyaan Keputusan untuk Product Owner & Tim Backend

Berikut 10 butir keputusan strategis yang memerlukan arahan resmi sebelum pengembangan kode dimulai:

1. **Model Privasi Koordinat (Bagian 5c)**:
   - *Opsi 1 (Direkomendasikan)*: Opsi A (Dual-resolution: koordinat presisi hanya untuk RT & pemilik; warga umum hanya melihat sel agregat ~150 m).
   - *Opsi 2*: Opsi B (Presisi untuk semua warga satu RT).
   - *Opsi 3*: Opsi C (Hanya fasum publik yang ditentukan RT).
   - *Rekomendasi Kami*: **Opsi 1 (Opsi A)** demi mematuhi invarian privasi INV-05 tanpa membatasi antusiasme warga.

2. **Penyedia Peta & Lisensi Tile (Bagian 5f)**:
   - *Opsi 1 (Direkomendasikan)*: `flutter_map` dengan provider tile gratis bertingkat atau self-hosted proxy OSM dengan caching agresif.
   - *Opsi 2*: `google_maps_flutter` dengan API Key Google Cloud Platform resmi (membutuhkan akun billing aktif).
   - *Opsi 3*: Peta ditunda; gunakan visualisasi daftar dan radar sederhana tanpa peta interaktif.
   - *Rekomendasi Kami*: **Opsi 1** (`flutter_map` + MapTiler / OpenMapTiles free tier) karena platform-agnostic dan mendukung offline disk cache.

3. **Lifecycle Foto vs Titik Pohon (INV-07)**:
   - *Opsi 1 (Direkomendasikan)*: Foto bukti dihapus permanen dari Storage setelah 30 hari, namun metadata titik pohon (waktu, jenis, status) tetap ada selamanya di Firestore.
   - *Opsi 2*: Foto disimpan permanen selama pohon masih hidup (membutuhkan perubahan invarian INV-07 dan penambahan kuota Storage).
   - *Rekomendasi Kami*: **Opsi 1** untuk menjaga kepatuhan privasi dan menekan biaya penyimpanan awan.

4. **Kamera In-App vs Galeri**:
   - *Opsi 1 (Direkomendasikan)*: Strict in-app camera only (warga wajib memotret langsung pohon di depan mereka).
   - *Opsi 2*: Mengizinkan warga mengunggah dari galeri HP (risiko foto unduhan Google/pemalsuan tinggi).
   - *Rekomendasi Kami*: **Opsi 1** guna menjaga integritas data gotong royong warga.

5. **Akurasi Minimum GPS & Mock Location**:
   - *Opsi 1 (Direkomendasikan)*: Tolak pengajuan jika akurasi GPS $> 30\text{ meter}$ atau flag mock location terdeteksi aktif.
   - *Opsi 2*: Izinkan toleransi hingga $100\text{ meter}$ untuk daerah dengan kanopi padat/gedung tinggi.
   - *Rekomendasi Kami*: **Opsi 1** (ambang batas $30\text{ m}$ dengan opsi mencoba kembali jika sinyal lemah).

6. **Hak Hapus Data Warga (`deleteOwnResidentData`)**:
   - *Opsi 1 (Direkomendasikan)*: Titik pohon tetap dipertahankan namun identitas pemilik dianonimkan menjadi `"Pohon Warga (Anonim)"`.
   - *Opsi 2*: Titik pohon milik warga tersebut langsung dihapus dari peta RT.
   - *Rekomendasi Kami*: **Opsi 1** agar data aset fisik resapan air lingkungan RT tetap akurat bagi kepentingan komunitas.

7. **Batas Wilayah RT (Geofence)**:
   - *Opsi 1 (Direkomendasikan)*: Radius lingkaran sederhana (mis. $300\text{–}500\text{ meter}$) dari titik pusat balai RT/RW.
   - *Opsi 2*: Polygon batas wilayah administratif RT resmi (memerlukan input data spasial GeoJSON dari operator RT).
   - *Rekomendasi Kami*: **Opsi 1** pada fase MVP karena kesederhanaan operasional bagi pengurus RT.

8. **Kategori Template Tugas Baru**:
   - Apakah Anda menyetujui penambahan kategori resmi baru `GREENING` (`Penghijauan`) pada katalog tugas terkunci dengan instruksi keselamatan hidrologis?
   - *Rekomendasi Kami*: **Setuju**, dengan instruksi keselamatan terkunci (larangan menanam di sempadan berbahaya dan jalur listrik).

9. **Peta Titik Kumpul Darurat (`emergency_directories`)**:
   - Apakah koordinat kasar titik kumpul evakuasi darurat (Batch 5 audit) digabungkan menjadi layer kedua pada peta yang sama?
   - *Rekomendasi Kami*: **Setuju**, sebagai layer ikon hijau/biru terpisah sehingga warga dapat melihat lokasi pohon sekaligus titik kumpul aman.

10. **Pemilik Eksekusi Backend**:
    - Apakah implementasi callable functions (Tahap T1–T2) dikerjakan oleh Tim Backend khusus, sementara pengembang client menunggu kontrak callable stabil?
    - *Rekomendasi Kami*: **Ya, tim backend mengerjakan T1–T2**, client Flutter mengimplementasikan UI kamera dan pratinjau (T3) dengan mock adapter hingga backend tersedia.

---
*(Dokumen selesai. Tidak ada kode fitur, izin Android, maupun dependensi baru yang ditambahkan pada tahap ini sesuai aturan gerbang).*
