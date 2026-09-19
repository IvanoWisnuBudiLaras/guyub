# Feature: Auth & Onboarding

Manajemen identitas dan sesi untuk Ketua RT/RW, Pendamping RT, dan Warga.

**Status:** Belum diimplementasikan pada Phase 0 (Phase 1).

## Rencana Layer
- `presentation/`: Screen, form dialog, widget tampilan.
- `application/`: State controller/notifier dan alur interaksi.
- `data/`: Repositori dan data source adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Firebase Auth hanya untuk operator (Ketua RT/RW dan Pendamping RT).\n- Warga bergabung menggunakan mekanisme scoped join code RT tanpa kredensial login rumit.\n- Dilarang mengumpulkan NIK, alamat lengkap, atau koordinat GPS presisi (PRD §18 PII Guardrail).

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat fase terkait.*
