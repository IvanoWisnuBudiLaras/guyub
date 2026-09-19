# Feature: Tasks (Tugas Kesiapsiagaan)

Lifecycle penugasan gotong royong kesiapsiagaan banjir warga RT/RW.

**Status:** Belum diimplementasikan pada Phase 0 (Phase 2).

## Rencana Layer
- `presentation/`: Screen, form dialog, widget tampilan.
- `application/`: State controller/notifier dan alur interaksi.
- `data/`: Repositori dan data source adapter.

## Invariant Penting (PRD & Acceptance Matrix)
- Weather suggestion dari BMKG TIDAK BOLEH otomatis menjadi ACTIVE task (AT-001). Wajib persetujuan operator RT.\n- Tugas warga harus berasal dari safe catalog yang terkontrol (AT-002).\n- Instruksi keselamatan inti bersifat immutable dan tidak boleh diubah operator (AT-003).\n- Partisipasi warga bersifat sukarela; aksi Decline ('Tidak Ikut') tersedia tanpa penalti (AT-004).\n- Tugas tersinkronisasi wajib dapat dibaca saat offline (AT-006, O-01).

*Perhatian: Jangan mengimplementasikan invariant di atas pada Phase 0; implementasikan saat fase terkait.*
