# Feature: Proposals (Usulan Warga)

Mekanisme warga mengusulkan titik rawan atau kebutuhan persiapan RT.

**Status:** Belum diimplementasikan pada Phase 0 (Phase 6 — Two-way Proposals and Assistance).

## Rencana Layer
- `presentation/`: Screen, form dialog, widget tampilan.
- `application/`: State controller/notifier dan alur interaksi.
- `data/`: Repositori dan data source adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Usulan warga TIDAK BOLEH aktif menjadi tugas secara otomatis (AT-012, S-08).
- Wajib ditinjau dan dipetakan oleh operator RT ke katalog tugas aman.

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat fase terkait.*
