# Kontrak API & Skema Data Fitur Titik Pohon (Tree Points)

Dokumen ini merupakan kontrak resmi antara **Backend (Firebase Cloud Functions + Firestore)** dan **Frontend (Flutter Client)** untuk fitur gotong royong penanaman pohon resapan air ("Pohon Guyub").

---

## 1. Model Privasi Koordinat (Dual-Resolution Model)

Berdasarkan keputusan resmi PO (Opsi A), koordinat dibagi menjadi dua tingkatan:

1. **Koordinat Kasar (Coarse Location)**:
   - Tingkat resolusi: Sel Geohash level 7 (perkiraan kotak $\pm 153\text{ m} \times 153\text{ m}$).
   - Terbuka untuk: Seluruh warga terautentikasi dan operator dalam RT yang sama.
   - Tersimpan di dokumen utama `tree_points/{treePointId}`.
2. **Koordinat Presisi (Exact Location)**:
   - Tingkat resolusi: Koordinat asli GPS perangkat (derajat desimal presisi tinggi).
   - Akses sangat terbatas: **Hanya** untuk Operator RT (Ketua RT/Pendamping) dan warga pembuat titik pohon terkait.
   - Tersimpan di sub-koleksi privat `tree_points/{treePointId}/private/location`.
   - Tidak pernah dikembalikan dalam response `listCommunityTreeMap`.

---

## 2. Struktur Dokumen Firestore

### Koleksi Utama: `tree_points`
Path dokumen: `tree_points/{treePointId}`
ID Dokumen: SHA-256 hash 40 karakter dari `${rtId}\0${taskId}\0${residentId}\0${plantedAtTimestamp}`

```typescript
interface TreePointDocument {
  treePointId: string;                 // Hex 40 karakter
  rtId: string;                        // ID RT wilayah pemilik
  taskId: string;                      // Relasi ke active task campaign (kategori GREENING)
  residentId: string;                  // Opaque ID warga (bukan NIK / identitas terbuka)
  submitterNickname: string;           // Nama panggilan warga (mis. "Pak Budi")
  speciesHint: string | null;          // Jenis pohon (opsional, maks 60 karakter, mis. "Mangga Arumanis")
  plantedAt: Timestamp;                // Waktu penanaman (server timestamp)
  clientReportedAt: Timestamp;         // Waktu pelaporan dari perangkat
  status: 'PENDING_RT_VERIFICATION' | 'VERIFIED' | 'REJECTED';
  rejectionReason: string | null;      // Catatan penolakan dari operator RT (jika REJECTED)
  verifiedByOperatorUid: string | null;// UID operator yang memverifikasi
  verifiedAt: Timestamp | null;        // Waktu verifikasi RT
  coarseLocation: {
    cellId: string;                    // Geohash precision 7
    approximateLat: number;            // Koordinat tengah sel kasar (Float)
    approximateLng: number;            // Koordinat tengah sel kasar (Float)
  };
  evidenceId: string | null;           // Relasi bukti foto di Storage (retensi 30 hari)
  evidenceExpiresAt: Timestamp | null; // Tanggal kedaluwarsa bukti foto
  isAnonymous: boolean;                // True jika pemilik meminta penghapusan profil (INV-05)
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

### Sub-Koleksi Privat: `private`
Path dokumen: `tree_points/{treePointId}/private/location`

```typescript
interface TreePointPrivateLocation {
  treePointId: string;
  exactLat: number;                    // Latitude presisi perangkat
  exactLng: number;                    // Longitude presisi perangkat
  accuracyMeters: number;              // Akurasi sensor GPS perangkat (wajib <= 30.0)
  isMocked: boolean;                   // Flag mock location perangkat (wajib false)
  recordedAt: Timestamp;
}
```

---

## 3. Spesifikasi Callable Cloud Functions

Semua interaksi client menggunakan Firebase Callable Functions dengan penegakan App Check terpusat.

### 3.1. `submitTreePoint`
- **Tujuan**: Mendaftarkan titik penanaman pohon baru oleh warga.
- **Mode Otorisasi**: `resident` (memerlukan `sessionToken` aktif).
- **Request Payload**:
  ```json
  {
    "sessionToken": "string (sesi warga aktif)",
    "taskId": "string (hex 40 karakter kampanye tugas aktif)",
    "speciesHint": "string? (opsional, maks 60 karakter)",
    "exactLat": -8.065432,
    "exactLng": 111.901234,
    "accuracyMeters": 14.5,
    "isMocked": false,
    "evidenceId": "string? (hex 40 karakter bukti foto terunggah)",
    "commandId": "string (idempotency key, 32-128 karakter)"
  }
  ```
- **Validasi Backend**:
  - `exactLat` di antara $-90.0$ dan $90.0$.
  - `exactLng` di antara $-180.0$ dan $180.0$.
  - `accuracyMeters` bertipe numerik dan $\le 30.0$ meter (jika $> 30.0$, ditolak dengan `failed-precondition: Akurasi GPS tidak memadai (maksimal 30 meter).`).
  - `isMocked` wajib `false` (jika `true`, ditolak dengan `permission-denied: Lokasi palsu (mock location) terdeteksi.`).
  - `speciesHint` disanitasi: dilarang memuat NIK, nomor HP, atau alamat rumah.
  - Perhitungan server: Menghasilkan `cellId` geohash level 7 dan titik tengah sel `approximateLat`/`approximateLng`.
- **Response Success**:
  ```json
  {
    "treePointId": "string",
    "status": "PENDING_RT_VERIFICATION",
    "coarseLocation": {
      "cellId": "string",
      "approximateLat": -8.065,
      "approximateLng": 111.901
    },
    "submittedAt": "2026-10-18T03:00:00.000Z"
  }
  ```

---

### 3.2. `listCommunityTreeMap`
- **Tujuan**: Mengambil daftar titik pohon yang telah terverifikasi untuk ditampilkan pada peta warga / operator.
- **Mode Otorisasi**: `resident` (via `sessionToken`) ATAU `operator` (via Firebase Auth token).
- **Request Payload (Warga)**:
  ```json
  {
    "sessionToken": "string"
  }
  ```
- **Request Payload (Operator)**:
  ```json
  {}
  ```
- **Response Success**:
  ```json
  {
    "items": [
      {
        "treePointId": "string",
        "speciesHint": "Mangga Arumanis",
        "submitterNickname": "Pak Budi",
        "isAnonymous": false,
        "coarseLocation": {
          "cellId": "string",
          "approximateLat": -8.065,
          "approximateLng": 111.901
        },
        "plantedAt": "2026-10-18T03:00:00.000Z",
        "hasEvidencePhoto": true
      }
    ],
    "totalVerifiedTrees": 1
  }
  ```
- **Catatan Keamanan**: Response **hanya memuat titik berstatus `VERIFIED`** dan **hanya memuat koordinat kasar**. Koordinat presisi tidak pernah diekspos dalam callable ini.

---

### 3.3. `verifyTreePoint`
- **Tujuan**: Operator RT menyetujui atau menolak titik pohon warga.
- **Mode Otorisasi**: `operator` (Ketua RT atau Pendamping RT aktif).
- **Request Payload**:
  ```json
  {
    "treePointId": "string",
    "decision": "APPROVE" | "REJECT",
    "rejectionReason": "string? (wajib diisi jika decision REJECT)",
    "commandId": "string (idempotency key)"
  }
  ```
- **Validasi Backend**:
  - Operator harus berada di RT yang sama dengan dokumen `tree_points`.
  - Dokumen harus berstatus `PENDING_RT_VERIFICATION`.
  - Operasi transaksional mencatat audit log dan memperbarui status secara atomik.
- **Response Success**:
  ```json
  {
    "treePointId": "string",
    "status": "VERIFIED" | "REJECTED",
    "verifiedAt": "2026-10-18T03:05:00.000Z"
  }
  ```

---

### 3.4. `deleteTreePoint`
- **Tujuan**: Menghapus titik pohon jika pohon mati, salah input, atau warga mencabut data.
- **Mode Otorisasi**:
  - `operator`: Dapat menghapus titik pohon mana saja dalam RT-nya.
  - `resident`: Hanya dapat menghapus titik pohon miliknya sendiri jika statusnya masih `PENDING_RT_VERIFICATION`.
- **Request Payload (Operator)**:
  ```json
  {
    "treePointId": "string",
    "reason": "string (alasan pencabutan titik pohon)"
  }
  ```
- **Response Success**:
  ```json
  {
    "deleted": true,
    "treePointId": "string"
  }
  ```

---

## 4. Invarian Privasi Saat Hapus Profil Warga (`deleteOwnResidentData`)

Sesuai keputusan Butir 6:
Saat warga menjalankan alur penghapusan data mandiri (`deleteOwnResidentData`):
1. Dokumen `tree_points` milik warga **tidak dihapus** dari peta RT demi integritas data resapan air lingkungan.
2. Field `submitterNickname` dianonimkan menjadi `"Pohon Warga (Anonim)"`.
3. Field `isAnonymous` diset menjadi `true`.
4. Sub-koleksi privat `private/location` dibersihkan dari atribut identifikasi dan bukti foto di Cloud Storage segera dijadwalkan untuk dihapus.
