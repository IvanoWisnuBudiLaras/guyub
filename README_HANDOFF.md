# Guyub.id AI Coding Handoff

Use these documents in this order:

1. `docs/GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md` — product truth, requirements, safety/privacy invariants, architecture and domain model.
2. `AGENTS.md` — operational rules for coding agents.
3. `docs/IMPLEMENTATION_PLAN.md` — phased build sequence.
4. `docs/TEST_ACCEPTANCE_MATRIX.md` — release-blocking verification matrix.
5. `docs/DEVELOPMENT.md` and `docs/REQUIREMENTS_TRACEABILITY.md` — development commands and current evidence/status.

The original competition proposal is included at `docs/MAGE 12_Tahap 1_AppDev_Tim Tidak Tau Diri.docx` with an extracted text companion. Where it does not specify enough technical detail, the Master PRD marks the section as **ENGINEERING DERIVATION** or **OPEN GAP**.

The coding agent must never silently convert a gap into a product behavior that weakens:
- human confirmation,
- task safety,
- voluntary participation,
- personal-data minimization,
- offline-critical availability.

No project-management or analytics service is required by this handoff package.
