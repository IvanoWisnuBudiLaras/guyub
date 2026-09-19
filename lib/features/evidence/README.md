# Feature: Evidence (Bukti Foto Persiapan)

Pengunggahan bukti foto opsional pelaksanaan tugas kesiapsiagaan dan pembersihan siklus hidup data.

**Status:** Belum diimplementasikan pada Phase 0 (Direncanakan pada Phase 8).

## Keputusan Provider: NOT A PRODUCTION PROVIDER / DEFERRED
- Firebase Cloud Storage **bukan** provider produksi karena ketiadaan kartu kredit / Firebase Blaze Plan.
- Emulator Storage tidak diaktifkan pada baseline Phase 0.
- Boundary storage/evidence dipertahankan pada layer application/data sebagai antarmuka abstrak agar provider (lokal/S3-compatible/alternatif) dapat ditentukan pada Phase 8.

## Rencana Layer
- `presentation/`: Image picker widget, viewer bukti terkompresi.
- `application/`: Workflow kompresi, stripping metadata EXIF, scheduled retention cleaner.
- `data/`: StorageBoundary interface dan repository adapter (provider ditentukan pada Phase 8).

## Invariant Penting (PRD & Acceptance Matrix)
- Bukti foto bersifat opsional; kegagalan upload foto tidak boleh menggagalkan status selesai tugas (ERR-06).
- Metadata lokasi (EXIF GPS) wajib dibersihkan sebelum disimpan (AT-010, P-02).
- Foto bukti wajib dihapus setelah masa retensi 30 hari berakhir (AT-011, P-03).
- Penghapusan bukti kedaluwarsa dapat diaudit/diverifikasi (SEC-09).

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat Phase 8.*
