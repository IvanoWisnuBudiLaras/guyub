# Guyub.id AI Coding Handoff

Use these documents in this order:

1. `GUYUB_ID_MASTER_PRD_ENGINEERING_SPEC.md` — product truth, requirements, safety/privacy invariants, architecture and domain model.
2. `AGENTS.md` — operational rules for coding agents.
3. `IMPLEMENTATION_PLAN.md` — phased build sequence.
4. `TEST_ACCEPTANCE_MATRIX.md` — release-blocking verification matrix.

## Important

The package is derived from the Guyub.id competition proposal. Where the proposal does not specify enough technical detail, the Master PRD marks the section as **ENGINEERING DERIVATION** or **OPEN GAP**.

The coding agent must never silently convert a gap into a product behavior that weakens:
- human confirmation,
- task safety,
- voluntary participation,
- personal-data minimization,
- offline-critical availability.

No project-management or analytics service is required by this handoff package.
