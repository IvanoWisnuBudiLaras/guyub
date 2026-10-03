# Feature: Tasks (Tugas Kesiapsiagaan)

Lifecycle penugasan gotong royong kesiapsiagaan banjir warga RT/RW.

**Status:** Phase 2 selesai diimplementasikan (Issue #13).

## Layer Structure
- `presentation/screens/`:
  - `task_catalog_screen.dart` (SCR-09): Katalog tugas aman, pemilihan template terkunci, pengisian slot deadline/lokasi/catatan, rendering instruksi keselamatan langsung (PRD §19).
  - `send_confirmation_screen.dart` (SCR-10): Konfirmasi pengiriman dengan ringkasan instruksi snapshot keselamatan terkunci (INV-01, INV-02) dan fitur salin teks WhatsApp warga (FR-TSK-005, O-06).
- `domain/`:
  - `models/task_template.dart`: Kontrak template aman terstandarisasi.
  - `models/task_campaign.dart`: State machine tugas (SUGGESTED -> DRAFT -> ACTIVE -> CLOSED/CANCELLED) & `InstructionSnapshot`.
  - `repositories/task_repository.dart`: Kontrak repositori tugas.
- `data/fake/`:
  - `fake_task_repository.dart`: Implementasi in-memory untuk pengujian & client standalone.

## Invariant Penting (PRD & Acceptance Matrix)
- **INV-01 / AT-001**: Pembuatan draft atau weather suggestion TIDAK PERNAH menghasilkan state `ACTIVE` secara otomatis. Transisi `ACTIVE` wajib melalui persetujuan eksplisit operator (`activateCampaign` di SCR-10).
- **INV-02 / AT-002**: Tugas warga wajib bersumber dari katalog template aman yang terkunci (`TaskTemplate`). Operator tidak dapat menulis instruksi bebas yang berisiko.
- **INV-02 / AT-003**: Instruksi keselamatan inti bersifat immutable melalui `InstructionSnapshot` dan tidak dapat diubah oleh operator RT.
- **FR-TSK-005 / O-06**: Salin ringkasan tugas dalam format siap tempel untuk grup WhatsApp RT, berfungsi tanpa ketergantungan FCM langsung.
- **AT-004**: Partisipasi warga bersifat sukarela; penolakan tugas tanpa penalti (Phase 3).
