# Feature: History & Handover

**Status: PARTIAL.** Operators can read paginated RT-owned history and a privacy-safe lifecycle timeline. Campaign records remain attached to the stable RT scope, not to the operator who created them.

## Implemented
- `listRtTaskHistory` derives RT authorization from current active operator membership. It returns ACTIVE/CLOSED/CANCELLED campaigns with immutable template/safety snapshots, deadlines, lifecycle timestamps, and an opaque bounded cursor. Drafts, resident IDs, names, notes, evidence references, and actor UIDs are excluded.
- An active campaign can be closed only by an explicit, confirmed, same-RT operator command. The backend hashes its idempotency key and atomically records one RT-owned audit event. Closure does not imply completion or RT verification and is never inferred from weather, deadline, or response count.
- `listTaskLifecycleEvents` checks RT scope and corresponding audit records, then returns only event type and timestamp. It does not expose actor IDs, command hashes, or raw audit documents.
- The operator history screen shows `Aktif`, `Ditutup`, or `Dibatalkan`, allows the operator to expand a lifecycle timeline, and opens the aggregate-only response recap. The recap counts verified completions but shows no resident rows, response denominator, or ranking.
- The history and lifecycle callables can be accessed by a replacement operator provisioned for the same RT. An operator transfer/provisioning UI is not implemented; trusted Firebase membership provisioning remains external.

## Validation and remaining work
- Functions service and Emulator tests cover close authorization/replay, resident exclusion, audit consistency, pagination, same-RT operator replacement, cross-RT isolation, and malformed records. PR #33 Java 21 Emulator CI passes.
- Android usability/accessibility and real pilot handover validation remain open. No history data is cached offline; the screen reports server load errors instead of showing stale data.
