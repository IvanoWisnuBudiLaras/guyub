# Feature: Emergency & Escalation (Darurat)

Direktori kontak darurat, titik kumpul evakuasi RT, dan rute eskalasi resmi.

**Status:** Belum diimplementasikan pada Phase 0 (Phase 7 — Emergency / Offline Mode).

## Rencana Layer
- `presentation/`: Screen, form dialog, widget tampilan.
- `application/`: State controller/notifier dan alur interaksi.
- `data/`: Repositori dan data source adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Kontak darurat dan titik kumpul RT wajib dapat diakses tanpa koneksi internet (AT-007).
- Masalah yang melampaui kapasitas RT dialihkan ke kanal resmi pemerintah/BPBD (AT-013). Guyub.id tidak menggantikan SAR/instansi resmi.

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat fase terkait.*
