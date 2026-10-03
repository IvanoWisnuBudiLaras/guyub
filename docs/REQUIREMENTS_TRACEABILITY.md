# Requirements Traceability Matrix — Guyub.id

Dokumen ini melacak pemenuhan spesifikasi teknis dari `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md` dan `TEST_ACCEPTANCE_MATRIX.md` terhadap kode sumber dan pengujian.

---

## 1. Traceability Phase 1: Authentication, Role Separation & RT-Code Session (Issue #12)

| Req ID | Deskripsi PRD | Invariant / Boundary | Lokasi Implementasi (Frontend / Client) | Lokasi Pengujian | Status |
|---|---|---|---|---|---|
| **FR-PRV-001** | Akses warga via RT-Code tanpa registrasi formal PII | INV-06: No NIK, No precise GPS | `lib/features/auth/application/entities/resident_session.dart`, `resident_rt_code_screen.dart` | `test/app/widget_test.dart` | ✅ Selesai |
| **FR-AUTH-001** | Autentikasi operator RT/RW via Email & Password | Auth boundaries decoupled | `lib/features/auth/presentation/screens/operator_login_screen.dart`, `auth_controller.dart` | `test/app/widget_test.dart` | ✅ Selesai |
| **SCR-01** | Splash screen dengan auto-restore session | Sesi tersimpan dipulihkan otomatis | `lib/features/auth/presentation/screens/splash_screen.dart`, `session_storage.dart` | `test/app/widget_test.dart` | ✅ Selesai |
| **SCR-02** | Role Selection Screen | Dua jalur terpisah (Operator vs Warga) | `lib/features/auth/presentation/screens/role_selection_screen.dart` | `test/app/widget_test.dart` | ✅ Selesai |
| **SEC-05** | Enumerasi kode RT tidak membocorkan data warga | ERR-04: Generic error message | `auth_controller.dart` (`joinAsResident`), `resident_rt_code_screen.dart` | `test/app/widget_test.dart` | ✅ Selesai |
| **SEC-01** | Larangan mutasi langsung Firestore tanpa autentikasi | Server-side boundary | `docs/handoff_backend_phase1.md` (Spesifikasi Firestore rules untuk backend) | Backend verification | ⏳ Menunggu backend |

---

## 2. Traceability Phase 2: Safe Task Catalog, Template Lock & Campaign Draft (Issue #13)

| Req ID | Deskripsi PRD | Invariant / Boundary | Lokasi Implementasi | Lokasi Pengujian | Status |
|---|---|---|---|---|---|
| **FR-TSK-001** | Katalog tugas aman terkontrol | INV-02: Safe task catalog locked | `lib/domain/models/task_template.dart`, `fake_task_repository.dart` | `test/features/tasks/task_campaign_test.dart` | ✅ Selesai |
| **FR-TSK-002** | Pengisian slot terbatas (deadline, lokasi, catatan) | Core & safety text read-only | `lib/features/tasks/presentation/screens/task_catalog_screen.dart` (SCR-09) | `test/features/tasks/task_screens_test.dart` | ✅ Selesai |
| **AT-002** | Tugas bebas/tanpa template aman ditolak | Invariant: Draft tidak boleh langsung ACTIVE | `lib/domain/models/task_campaign.dart`, `fake_task_repository.dart` | `test/features/tasks/task_campaign_test.dart` (`AT-002`) | ✅ Selesai |
| **AT-003** | Teks instruksi keselamatan immutable | `InstructionSnapshot` terkunci dari modifikasi template masa depan | `lib/domain/models/task_campaign.dart` (`InstructionSnapshot`) | `test/features/tasks/task_campaign_test.dart` (`AT-003`) | ✅ Selesai |
| **INV-01** | Human approval before distribution | Transisi `DRAFT -> ACTIVE` hanya via tindakan sadar operator | `lib/features/tasks/presentation/screens/send_confirmation_screen.dart` (SCR-10) | `test/features/tasks/task_campaign_test.dart` (`INV-01`), `task_screens_test.dart` | ✅ Selesai |
| **PRD §19** | Instruksi keselamatan tidak tersembunyi saat actionable | Instruksi keselamatan ditampilkan jelas pada card & confirmation | `lib/features/tasks/presentation/screens/task_catalog_screen.dart`, `send_confirmation_screen.dart` | `test/features/tasks/task_screens_test.dart` | ✅ Selesai |
| **FR-TSK-005** | Tombol salin ringkasan tugas untuk WhatsApp RT | O-06: Tetap dapat disebarkan manual tanpa ketergantungan FCM | `lib/features/tasks/presentation/screens/send_confirmation_screen.dart` (`_copyWhatsAppText`) | `test/features/tasks/task_screens_test.dart` (`FR-TSK-005 & O-06`) | ✅ Selesai |
| **SEC-03** | Aktivasi kampanye tugas bersifat idempoten | Mencegah duplikasi aktivasi saat retry | `lib/data/fake/fake_task_repository.dart` | `test/features/tasks/task_campaign_test.dart` (`Idempotency`) | ✅ Selesai |
