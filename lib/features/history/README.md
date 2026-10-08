# Feature: History & Handover

**Status: PARTIAL.** Operators can read a paginated RT-owned task history from the server. Campaign records remain attached to the stable RT scope, not to the operator who created them.

## Implemented
- `listRtTaskHistory` derives RT authorization from the current active operator membership. It returns only ACTIVE/CANCELLED campaigns, immutable template/safety snapshots, deadlines, activation/cancellation times, and an opaque bounded cursor. Drafts, resident IDs, names, notes, evidence references, and actor UIDs are excluded.
- The read-only operator screen supports pagination and opens the existing aggregate-only response recap. The recap counts verified completions but shows no resident rows, response denominator, or ranking.
- The history callable and recap can be accessed by a replacement operator provisioned for the same RT. An operator transfer/provisioning UI is not implemented; trusted Firebase membership provisioning remains external.

## Remaining validation
- Functions tests cover pagination, same-RT operator replacement, cross-RT isolation, and malformed record rejection.
- Android usability/accessibility and real pilot handover validation remain open. No history data is cached offline; the screen reports server load errors instead of showing stale data.
