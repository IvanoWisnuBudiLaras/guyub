# Feature: Assistance (Dukungan Warga Rentan)

Penandaan kebutuhan bantuan warga lansia/difabel dan status proxy helper.

**Status:** Belum diimplementasikan pada Phase 0 (Phase 6 — Two-way Proposals and Assistance).

## Rencana Layer
- `presentation/`: Screen, form dialog, widget tampilan.
- `application/`: State controller/notifier dan alur interaksi.
- `data/`: Repositori dan data source adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Operator RT dapat memperbarui status atas nama warga non-aplikasi (AT-014 proxy status).
- Dilarang membocorkan data medis sensitif ke publik/tetangga tanpa izin (P-06).

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat fase terkait.*
