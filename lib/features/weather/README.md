# Feature: Weather (BMKG Open Data)

Integrasi data cuaca terbuka BMKG dan evaluasi threshold peringatan dini lokal.

**Status:** Belum diimplementasikan pada Phase 0 (Direncanakan pada Phase 4).

## Rencana Layer
- `presentation/`: Screen, widget cuaca, banner indikator status siaga.
- `application/`: Rule evaluation service, BMKG polling workflow, task suggestion generator.
- `data/`: BMKG remote client, local weather cache adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Evaluasi cuaca hanya menghasilkan Task Suggestion, bukan task aktif otomatis (AT-001).
- Kegagalan koneksi BMKG tidak boleh menghapus snapshot cuaca valid terakhir (ERR-01, O-05).
- Data cuaca cache saat offline wajib menampilkan penanda stale/timestamp (AT-008).

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat Phase 4.*
