# Guyub.id — Master PRD & Engineering Specification

**Status:** Implementation handoff baseline  
**Product:** Guyub.id  
**Platform:** Android APK  
**Primary source:** `MAGE 12_Tahap 1_AppDev_Tim Tidak Tau Diri(1).docx` (26 pages)  
**Purpose of this document:** Convert the competition proposal into an implementation-ready specification that an AI coding agent can execute without silently changing the product intent.

---

## 0. Source-of-truth and interpretation rules

This document deliberately separates three kinds of statements:

- **SOURCE REQUIREMENT** — directly supported by the proposal and must not be changed by an implementation agent without human approval.
- **ENGINEERING DERIVATION** — a technical structure inferred to make a source requirement implementable. It may be changed if the same externally observable behavior and safety/privacy invariants are preserved.
- **OPEN GAP** — the proposal does not specify enough detail. The agent must use the default decision written here or stop and request a product decision if the default cannot be implemented safely.

### Precedence

When documents disagree, use this order:

1. Safety and privacy invariants in this specification.
2. Explicit product behavior in the original Guyub.id proposal.
3. This Master PRD & Engineering Specification.
4. Implementation plan.
5. Existing code.
6. Agent preference or framework convention.

An implementation agent MUST NOT reinterpret Guyub.id as:
- a flood prediction system at RT level,
- an official emergency warning system,
- a replacement for BPBD or government reporting channels,
- an application that automatically orders residents to take risky actions.

---

# 1. Product definition

## 1.1 Product summary

**SOURCE REQUIREMENT**

Guyub.id is an Android application that helps RT/RW communities perform flood-preparedness activities in a coordinated, safe, and recorded way.

The product closes the gap between **early warning** and **early action**. Weather/risk information already exists, but residents still need:
1. a clear action to take,
2. a trusted local coordinator,
3. safety constraints,
4. tracking of who has responded,
5. historical preparedness records.

The central product principle is:

> **Automation handles repetitive work; humans handle risky decisions.**

The system may automate weather retrieval, threshold detection, preparation suggestions, distribution, reminders, recap, escalation, and evidence retention. The final decision to send safety-related preparation tasks remains with Ketua RT/RW or an authorized Pendamping RT.

**Source mapping:** file pp. 3–5, 12–14.

---

# 2. Problem statement

## 2.1 Surface problem

Residents commonly receive flood/rain information through WhatsApp, social media, or local leaders. These channels are fast, but they do not reliably answer:

- what practical preparation should be done now,
- who is responsible for coordinating it,
- whether the action is safe,
- who has already responded,
- what happened during the previous incident.

**Source mapping:** file pp. 4–5, 14–15.

## 2.2 Operational problem

Current coordination depends too heavily on manual work by RT/RW leaders:
- manually reading weather information,
- composing messages,
- repeatedly reminding residents,
- counting responses,
- identifying residents who may need help,
- reconstructing old preparedness history from chat messages.

Guyub.id turns these activities into a persistent, structured workflow.

## 2.3 Product hypothesis

If safe preparation tasks are converted into structured, time-bounded, voluntary workflows with human confirmation and automatic reminders/recap, then RT/RW communities should be able to understand, perform, and record preparedness actions more consistently.

The proposal explicitly does **not** claim a quantified reduction in flood losses before field validation.

**Source mapping:** file pp. 6–7.

---

# 3. Goals, success criteria, and non-goals

## 3.1 Goals

**SOURCE REQUIREMENT**

G-01. Automate BMKG weather retrieval and refresh.  
G-02. Detect configured weather thresholds and prepare task suggestions.  
G-03. Reduce administrative work for Ketua RT/RW.  
G-04. Ensure every resident-facing task comes from a safe task catalog.  
G-05. Keep core safety instructions immutable.  
G-06. Preserve voluntary participation.  
G-07. Allow residents to propose tasks and flag neighbors who need assistance.  
G-08. Preserve preparedness history across incidents and leadership changes.  
G-09. Redirect issues requiring official intervention to official reporting channels.  
G-10. Remain useful during connectivity disruption.

**Source mapping:** file pp. 6, 12–14.

## 3.2 MVP success criteria

**SOURCE REQUIREMENT**

The initial validation target is not “prevent flooding” or “reduce losses by X%.” The MVP should validate whether:
- preparation tasks are understandable,
- preparation tasks can be performed safely,
- participation/status can be recorded,
- the workflow is usable by RT/RW and residents.

**Source mapping:** file p. 6.

## 3.3 Non-goals

**SOURCE REQUIREMENT**

NG-01. Do not predict flooding at RT-level granularity.  
NG-02. Do not publish an official disaster warning.  
NG-03. Do not send resident tasks without RT/RW approval.  
NG-04. Do not allow inherently risky tasks such as entering drainage channels or operating during dangerous weather.  
NG-05. Do not force participation.  
NG-06. Do not rank residents.  
NG-07. Do not publish resident photos, full addresses, or GPS coordinates.  
NG-08. Do not replace BPBD, SP4N-LAPOR!, JAKI, or other official services.  
NG-09. Do not expand the MVP to disasters other than flood/rain-related inundation.

**Source mapping:** file pp. 8–9.

---

# 4. MVP boundaries

**SOURCE REQUIREMENT**

- Android mobile application.
- Distributed as `.apk`.
- Disaster scope: flood and rain-related inundation only.
- Pilot scope: one kelurahan, three to five RT.
- Pilot participation target: approximately 50–100 households.
- Internet is required for synchronization.
- Offline mode must still show:
  - active tasks,
  - last weather forecast and its update timestamp,
  - emergency contacts,
  - assembly/evacuation points.
- Pilot location is not yet fixed in the proposal.

**Source mapping:** file pp. 8–10.

---

# 5. User roles and authorization model

## 5.1 Ketua RT/RW

**SOURCE REQUIREMENT**

Primary operator. Can:
- authenticate using email/password,
- inspect weather context and local conditions,
- review task suggestions,
- select safe task templates,
- fill limited task parameters,
- approve and send tasks,
- monitor response recap,
- verify task completion,
- record proxy status for residents who do not use the app,
- manage vulnerable-resident assistance,
- direct issues to official channels.

## 5.2 Pendamping RT

**SOURCE REQUIREMENT**

Secretary or resident appointed by Ketua RT. Has equivalent operational rights to send tasks when Ketua RT is unavailable.

The product must support multiple authorized operators while keeping a trace of who performed each administrative action.

## 5.3 Warga

**SOURCE REQUIREMENT**

Residents:
- do not create formal accounts,
- join using an RT code,
- receive preparation tasks,
- choose to join or not join voluntarily,
- confirm completion,
- propose new tasks / report local conditions,
- flag neighbors who may need help,
- can contribute without being publicly ranked.

## 5.4 Warga without application access

**SOURCE REQUIREMENT**

Elderly residents, residents with disabilities, and people without smartphones must not be excluded from the preparedness record. Their status may be represented and updated by RT/RW as a proxy.

**Source mapping:** file pp. 9–10, 22–23.

---

# 6. Immutable product and safety invariants

These rules are **hard constraints**. An AI coding agent must treat a violation as a failed build even if the UI appears functional.

## INV-01 — Human approval before distribution

A weather threshold may create a **suggestion**, but it must never directly create a resident-visible active task.

Required path:

`weather data -> threshold evaluation -> suggested task package -> RT review -> explicit confirmation -> distribution`

## INV-02 — Safe catalog only

RT/RW must not author arbitrary safety-critical task instructions from scratch.

A task is created from a safe template. Only limited slots are editable:
- deadline,
- location reference,
- short additional note.

Core instruction and safety text are immutable for operators.

## INV-03 — Voluntary participation

Every resident-facing task must permit a clear non-participation choice.

No participation leaderboard, shaming, penalty, forced confirmation, or dark pattern.

## INV-04 — No risky task execution

The safe task catalog must exclude actions such as:
- entering drains or sewers,
- approaching dangerous flowing water,
- performing tasks during unsafe weather,
- any task requiring specialized emergency response.

## INV-05 — Source transparency

Weather information must show:
- BMKG attribution,
- last source update timestamp,
- stale/offline state when cached data is shown.

## INV-06 — Minimal personal data

The system must not store:
- NIK,
- full residential address,
- precise GPS coordinates.

Allowed/minimal data from proposal:
- RT identity,
- nickname,
- optional house number,
- task participation/status.

## INV-07 — Evidence privacy

Optional photo evidence:
- must not be mandatory for every task,
- must have location metadata removed before upload/storage,
- must be automatically deleted after 30 days.

## INV-08 — Offline-critical information

Emergency contacts and assembly points must remain readable without internet.

Active task and last-known weather information must remain readable offline.

## INV-09 — Government escalation, not replacement

When a problem exceeds community capacity, the app directs the user to the appropriate official channel.

## INV-10 — Persistent preparedness record

Historical task completion must belong to the RT/community context, not only to the current leader’s personal device/account.

---

# 7. Core user journeys

## J-01 — Role selection and entry

**Source/UI basis: file p. 17.**

1. App opens.
2. User chooses:
   - “Saya Ketua RT/RW” / formal operator path, or
   - “Saya Warga” / RT-code path.
3. Operator authenticates with account credentials.
4. Resident enters RT code.
5. App routes to role-specific home/navigation.

## J-02 — Weather to suggested preparation

1. Scheduled backend retrieves BMKG forecast.
2. System stores source timestamp.
3. Configured threshold evaluator runs.
4. If threshold condition is met, system creates one or more safe task suggestions.
5. No task is sent yet.
6. Ketua RT/RW inspects:
   - weather context,
   - current local condition,
   - suggested preparation.
7. Operator may accept, postpone, or ignore the suggestion.

## J-03 — Create and confirm task

**Source/UI basis: file p. 21.**

1. Operator opens Task Catalog.
2. Selects safe locked template.
3. Enters:
   - deadline,
   - location note/reference,
   - optional short note.
4. System shows confirmation summary:
   - task,
   - recipients,
   - deadline,
   - location,
   - immutable safety instruction.
5. Operator explicitly presses send.
6. Task becomes active.
7. Residents receive in-app/FCM notification.
8. App provides a copyable text version for WhatsApp distribution.

## J-04 — Resident participation

**Source/UI basis: file pp. 18–19.**

1. Resident sees active tasks.
2. Resident may view task details.
3. Resident selects:
   - participate, or
   - not participate.
4. If participating, resident follows the safe instructions.
5. Resident may submit completion.
6. Optional proof and a short report may be attached if the task supports it.
7. Completion enters “Menunggu Verifikasi RT”.
8. RT/RW verifies the result before it counts as officially completed.

## J-05 — Reminder and escalation

1. Scheduler checks open tasks.
2. Before deadline, non-responding participants receive reminder(s).
3. When configured escalation conditions are reached, Pendamping RT is notified.
4. Escalation is administrative; it must not convert voluntary participation into coercion.

## J-06 — Resident proposes task / local condition

**Source/UI basis: file p. 20.**

1. Resident opens “Usulkan Tugas Baru”.
2. Resident may enter:
   - title,
   - description,
   - location reference,
   - optional supporting photo,
   - category.
3. Suggestion goes to RT/RW.
4. Resident suggestion must **not** directly become an executable task.
5. RT/RW must map/convert it to a safe catalog template if action is appropriate.

## J-07 — Vulnerable resident assistance

**Source/UI basis: file pp. 20 and 22.**

1. RT/RW records/marks a household that may need assistance.
2. System shows assistance state.
3. A nearby willing helper may be paired with the household.
4. The helper task remains voluntary and must use safe instructions.
5. RT/RW can update the status for a household without app access.

## J-08 — Emergency/offline information

**Source/UI basis: file pp. 19 and 22.**

1. User opens “Darurat”.
2. App shows offline/last-sync indicator.
3. App shows configured:
   - emergency phone numbers,
   - assembly/evacuation points,
   - verification status/notes when applicable.
4. This content must be stored locally and usable without a network connection.

## J-09 — Official escalation

1. User/RT identifies an issue outside community capacity.
2. App explains that the issue needs official handling.
3. App directs user to configured official channel (e.g. SP4N-LAPOR!, BPBD; JAKI only where applicable).
4. Guyub.id does not represent the report as handled until the official system provides evidence/status.

---

# 8. Functional requirements

## 8.1 Weather and context

### FR-WTH-001 — BMKG forecast retrieval
Backend retrieves BMKG forecast on a schedule.

**Acceptance:**
- cached snapshot is timestamped,
- source attribution is preserved,
- retrieval failure does not erase the last valid snapshot.

### FR-WTH-002 — Staleness
UI always distinguishes live/recently synchronized data from cached/offline data.

### FR-WTH-003 — Threshold evaluation
Weather values may trigger suggestions.

**OPEN GAP:** Proposal provides no numeric threshold values.  
**Default engineering decision:** thresholds are configuration data, never hidden constants in application code.

### FR-WTH-004 — No RT-level prediction claim
UI copy must say “forecast/weather context,” not “RT flood prediction.”

---

## 8.2 Safe task catalog

### FR-TSK-001 — Locked template
Each template contains:
- template ID,
- title,
- category,
- core instructions,
- immutable safety instructions,
- estimated/typical duration if known,
- enabled/disabled status.

### FR-TSK-002 — Editable slots
Operator may edit only:
- deadline,
- local location reference,
- short additional note.

### FR-TSK-003 — Task categories
The proposal/mockups indicate examples such as:
- infrastructure/drainage inspection from a safe position,
- logistics,
- household preparation,
- environmental cleanup,
- emergency-related proposals.

Category naming may be normalized in implementation, but must not imply that residents perform professional emergency-response work.

### FR-TSK-004 — Explicit send confirmation
No resident delivery occurs before explicit operator confirmation.

### FR-TSK-005 — WhatsApp copy text
Provide a button/action to copy a human-readable task summary for existing RT WhatsApp groups.

---

## 8.3 Participation and completion

### FR-PAR-001 — Join/decline
Residents can explicitly choose “Ikut” or “Tidak Ikut”.

### FR-PAR-002 — No coercion
Declining a task must not trigger a punitive UI.

### FR-PAR-003 — Completion submission
Participant can mark a joined task as completed.

### FR-PAR-004 — Verification
Resident-completed task remains pending until RT/RW verification.

### FR-PAR-005 — Proxy update
Authorized operator may update status for residents without app access.

### FR-PAR-006 — Optional evidence
Evidence is optional and limited.

### FR-PAR-007 — History
Verified completion contributes to RT preparedness history.

---

## 8.4 Reminders and escalation

### FR-REM-001
System can schedule reminders before task deadline.

### FR-REM-002
System can identify non-response.

### FR-REM-003
System can notify Pendamping RT when a task is not being responded to according to configured rules.

**OPEN GAP:** Proposal does not define exact reminder times or escalation thresholds.  
**Default:** store these as configuration per environment/RT; seed conservative demo values rather than hard-code product truth.

---

## 8.5 Two-way coordination

### FR-TWO-001
Resident can propose a preparation task/local issue.

### FR-TWO-002
Proposal requires RT review before becoming an active safe task.

### FR-TWO-003
Resident may flag a neighbor/household needing assistance.

### FR-TWO-004
System supports helper assignment without public exposure of sensitive household information.

---

## 8.6 Emergency and official channels

### FR-EMG-001
Emergency numbers are locally cached.

### FR-EMG-002
Assembly points are locally cached.

### FR-EMG-003
Official reporting links/actions are configurable by pilot area.

### FR-EMG-004
Mockup-specific phone numbers and locations are **demo content**, not product constants.

---

## 8.7 Privacy and retention

### FR-PRV-001
Do not collect NIK.

### FR-PRV-002
Do not collect full address.

### FR-PRV-003
Do not collect precise resident GPS.

### FR-PRV-004
Photo geolocation metadata is removed before server persistence.

### FR-PRV-005
Evidence automatically expires and is deleted after 30 days.

### FR-PRV-006
Residents can request/delete their own data.

**OPEN GAP:** Residents have no formal account, so identity verification for self-deletion is unspecified. See §15.4 default mechanism.

---

# 9. Screen inventory derived from the proposal UI

The proposal contains concrete mockups on file pp. 17–22. These screens are part of the intended product behavior and should be implemented before adding unrelated screens.

## SCR-01 — Splash
- Guyub.id logo.
- Fast route to role selection.

## SCR-02 — Role selection
- “Saya Ketua RT/RW”
- “Saya Warga”
- Explanatory subtitle for each path.

## SCR-03 — Warga Home
Observed elements:
- RT/RW badge/context,
- greeting,
- date,
- weather card,
- precipitation/rainfall/wind context,
- task summary counts,
- priority task card,
- “Semua Tugas”,
- “Usulkan Tugas Baru”,
- bottom navigation: Beranda / Tugas / Darurat.

## SCR-04 — Warga Task List
Task cards show:
- urgency/category,
- time remaining/deadline,
- title,
- action to view details,
- action to join / state “Saya Ikut”.

## SCR-05 — Completion
Observed elements:
- task title,
- optional photo evidence,
- 30-day deletion notice,
- short report note,
- confirmation checklist,
- “Tandai Selesai”.

The exact confirmation checklist content is template-specific.

## SCR-06 — Emergency
Observed elements:
- offline/last-updated state,
- emergency number cards,
- evacuation/assembly points,
- verification state,
- important safety note,
- bottom navigation.

## SCR-07 — Propose Task
Observed elements:
- title,
- description,
- location reference,
- optional photo,
- category,
- submit to RT.

## SCR-08 — RT/RW Home
Observed elements:
- RT identity/greeting,
- weather context,
- “kesiapan rumah tangga” summary,
- pending verification cards,
- task status counters,
- “Kirim tugas baru”,
- recent tasks,
- role-specific navigation.

## SCR-09 — Task Catalog
Observed elements:
- locked-template notice,
- selectable safe template,
- category/duration,
- deadline,
- local location note,
- additional note,
- proceed to confirmation.

## SCR-10 — Send Confirmation
Observed elements:
- task title,
- recipient count,
- deadline,
- location,
- recipient preview,
- notification warning,
- explicit “Kirim Ke Warga”.

## SCR-11 — Vulnerable Residents
Observed elements:
- explanation banner,
- household/person cards,
- assistance tags,
- assignment/helper state,
- add vulnerable resident.

---

# 10. State machines

The proposal describes behavior but does not define enum names. The following names are **ENGINEERING DERIVATIONS** and may be renamed while preserving transitions.

## 10.1 Task campaign state

```text
SUGGESTED
   |
   | operator selects/reviews
   v
DRAFT
   |
   | explicit confirmation
   v
ACTIVE
   |
   +----> CLOSED
   |
   +----> CANCELLED_BY_OPERATOR
```

Rules:
- `SUGGESTED` is never resident-visible as an instruction.
- `DRAFT` cannot emit resident notifications.
- only authorized operator can transition `DRAFT -> ACTIVE`.
- cancellation must retain an audit record.

## 10.2 Resident response state

```text
UNRESPONDED
  | \
  |  \ decline
  |   -> DECLINED
  |
  | join
  v
JOINED
  |
  | submit completion
  v
PENDING_RT_VERIFICATION
  |
  | verified
  v
VERIFIED_COMPLETE
```

No state may represent punishment for declining.

## 10.3 Proposal state

```text
SUBMITTED
  |
  +--> DISMISSED
  |
  +--> NEEDS_OFFICIAL_REPORT
  |
  +--> MAPPED_TO_SAFE_TEMPLATE -> DRAFT TASK
```

A resident proposal must never bypass the safe catalog.

---

# 11. System architecture

## 11.1 Stack required by proposal

**SOURCE REQUIREMENT**

- Flutter — Android application.
- Firebase Firestore — RT, task, response/status data; offline synchronization.
- Firebase Authentication — Ketua RT/RW and Pendamping RT only.
- Firebase Cloud Functions — scheduled automation.
- Firebase Cloud Messaging — notifications.
- BMKG Open Data — weather source.
- Figma — design workflow.
- GitHub — source collaboration.

The proposal states Firestore storage region `asia-southeast2 (Jakarta)`. Implementation must verify that the selected Firebase products and project configuration support the intended data-location requirement before production/pilot deployment; do not silently fall back to another region.

**Source mapping:** file pp. 11–12.

## 11.2 Runtime component map

```text
+------------------------+
| BMKG Open Data         |
+-----------+------------+
            |
            v
+------------------------+
| Cloud Functions        |
| - scheduled fetch      |
| - threshold evaluator  |
| - suggestion builder   |
| - reminders/escalation |
| - evidence cleanup     |
+----+---------------+---+
     |               |
     v               v
+---------+      +---------+
|Firestore|      |   FCM   |
+----+----+      +----+----+
     |                |
     +--------+-------+
              |
              v
      +---------------+
      | Flutter Android|
      | local cache    |
      | offline queue  |
      +---------------+
```

## 11.3 Engineering extension required for photo evidence

**OPEN GAP**

The proposal requires optional photo evidence and 30-day deletion but does not name a binary-object storage service.

**Default engineering decision:** use Firebase Cloud Storage for image bytes and keep only metadata/reference in Firestore. This is an implementation extension, not a product feature change.

If Cloud Storage is not permitted by project constraints, the agent must stop and request a storage decision rather than place large image binaries in Firestore documents.

---

# 12. Logical domain model

The following schema is an implementation-oriented derivation.

## 12.1 `rt_communities`

Represents persistent community context.

Fields:
- `id`
- `kelurahanName`
- `rtLabel`
- `rwLabel`
- `displayName`
- `joinCodeHash` or server-side join mapping
- `timezone`
- `reminderPolicyId`
- `createdAt`
- `updatedAt`

Never store exact resident GPS coordinates.

## 12.2 `operators`

Fields:
- `uid` — Firebase Auth UID
- `rtId`
- `role` = `KETUA_RT_RW | PENDAMPING_RT`
- `displayName`
- `active`
- timestamps

## 12.3 `resident_profiles`

Resident records are not formal Firebase Auth accounts.

Fields:
- `residentId`
- `rtId`
- `nickname`
- `houseNumberOptional`
- `needsAssistance`
- `deviceBoundParticipantIdOptional`
- `createdBy` = self/proxy
- timestamps

Do not add NIK/full address/GPS.

## 12.4 `weather_snapshots`

Fields:
- `rtId` or `kelurahanKey`
- `source = BMKG`
- `sourceUpdatedAt`
- `fetchedAt`
- normalized forecast fields required by UI
- `rawReference` or raw payload subset
- `isLastValid`

## 12.5 `weather_rules`

Configurable because the proposal does not define numeric thresholds.

Fields:
- `ruleId`
- `scope`
- `enabled`
- condition definition
- suggested template IDs
- explanation copy

Rules create suggestions, never active tasks.

## 12.6 `task_templates`

Fields:
- `templateId`
- `title`
- `category`
- `coreInstruction`
- `safetyInstruction`
- `estimatedDurationOptional`
- `enabled`
- `version`

Core and safety text are immutable in the RT UI.

## 12.7 `task_suggestions`

Fields:
- `suggestionId`
- `rtId`
- `triggerSnapshotId`
- `ruleId`
- recommended template IDs
- `state`
- timestamps

## 12.8 `task_campaigns`

Fields:
- `taskId`
- `rtId`
- `templateId`
- `templateVersion`
- immutable instruction snapshot
- `deadline`
- `locationNote`
- `additionalNote`
- `state`
- `createdByOperatorUid`
- `approvedByOperatorUid`
- timestamps

Keep an immutable snapshot so old task history does not change if a template is edited later.

## 12.9 `task_responses`

Fields:
- `taskId`
- `residentId`
- `participationState`
- `completionState`
- `completionNoteOptional`
- `evidenceIdOptional`
- `verifiedByOperatorUidOptional`
- timestamps

## 12.10 `resident_proposals`

Fields:
- `proposalId`
- `rtId`
- `residentId`
- `title`
- `description`
- `locationReference`
- `category`
- `evidenceIdOptional`
- `state`
- timestamps

## 12.11 `assistance_assignments`

Fields:
- `assignmentId`
- `rtId`
- `residentNeedingHelpId`
- `helperResidentIdOptional`
- `taskIdOptional`
- `state`
- timestamps

## 12.12 `emergency_directory`

Fields:
- `rtId`
- `emergencyContacts[]`
- `assemblyPoints[]`
- `officialReportChannels[]`
- `lastVerifiedAt`
- `version`

This collection is cached locally.

## 12.13 `audit_events`

Administrative/safety-relevant actions:
- task approved,
- task sent,
- task cancelled,
- resident completion verified,
- assistance record changed,
- emergency directory changed,
- template version changed.

Audit data must avoid unnecessary personal information.

---

# 13. Resident access without formal accounts

This is the largest implementation ambiguity in the proposal.

## 13.1 Source constraint

The proposal explicitly says Firebase Authentication is only for Ketua RT/RW and Pendamping RT. Residents enter using an RT code and do not create accounts.

## 13.2 Security consequence

An unauthenticated mobile client must not be given broad direct Firestore write permissions. An RT code alone must not become permanent authorization for modifying arbitrary resident/task records.

## 13.3 Default engineering mechanism

Use a backend-mediated resident session:

1. Resident enters RT code.
2. App calls a Cloud Function to resolve/validate the code.
3. Function returns:
   - non-sensitive RT profile,
   - short-lived/scoped resident access token or opaque participant session,
   - server-generated `participantId`.
4. Participant token is stored securely on device.
5. Resident writes go through callable/HTTP Cloud Functions that validate:
   - token,
   - RT scope,
   - task scope,
   - allowed transition.
6. Firestore rules deny unauthenticated direct mutation of protected collections.
7. Public/readable data is limited to what is required for the resident’s RT context.

This preserves “no resident account” while avoiding open database writes.

The exact cryptographic/session implementation is an engineering choice, but the authorization boundary is mandatory.

---

# 14. Backend jobs and commands

Names below are implementation suggestions.

## CF-01 `syncBmkgForecast`
Responsibilities:
- fetch official BMKG source,
- validate response,
- normalize required values,
- persist last valid snapshot,
- keep previous valid snapshot on failure,
- record source update time.

## CF-02 `evaluateWeatherRules`
Responsibilities:
- evaluate configured rules against latest valid forecast,
- create idempotent task suggestions,
- never activate a task.

## CF-03 `activateTaskCampaign`
Callable by authenticated operator.
Responsibilities:
- verify operator belongs to RT,
- validate safe template/version,
- validate deadline/location/note,
- persist immutable task snapshot,
- transition to ACTIVE,
- enqueue notifications.

## CF-04 `submitResidentResponse`
Responsibilities:
- validate resident session,
- enforce allowed state transition,
- update only that participant’s response.

## CF-05 `submitCompletion`
Responsibilities:
- accept completion note,
- attach optional evidence reference,
- transition to pending RT verification.

## CF-06 `verifyCompletion`
Authenticated operator only.

## CF-07 `sendTaskReminders`
Scheduled.
Must be idempotent.

## CF-08 `escalateUnrespondedTasks`
Scheduled.
Notifies operator/pendamping; does not punish resident.

## CF-09 `deleteExpiredEvidence`
Scheduled.
Deletes evidence after 30 days and clears/marks metadata.

## CF-10 `submitResidentProposal`
Resident session required.
Does not create active task.

---

# 15. Privacy and data lifecycle

## 15.1 Data minimization

Required:
- collect only fields necessary for coordination,
- avoid identity fields not required by MVP,
- separate emergency/community data from resident personal data.

## 15.2 Photo handling

Pipeline:

```text
select/capture photo
-> remove EXIF/location metadata on device
-> optional local resize/compression
-> upload
-> store minimal evidence metadata
-> schedule/record expiryAt = createdAt + 30 days
-> automatic deletion
```

Do not depend only on UI hiding. Physical object deletion is required.

## 15.3 Data deletion

Source says residents may delete their data.

## 15.4 Default resident self-deletion mechanism

Because residents have no formal account:

- Same-device deletion may be authorized using the resident participant token.
- If token/device is unavailable, deletion is handled by an authorized RT operator after an offline identity-verification procedure defined for the pilot.
- Product UI must not promise identity recovery that has not been implemented.

This is an **ENGINEERING DERIVATION** needed to make the source requirement operational.

---

# 16. Offline-first behavior

## 16.1 Must work offline

- last valid weather snapshot,
- source update timestamp,
- active tasks already synchronized,
- emergency numbers,
- assembly points,
- safe task instructions already synchronized.

## 16.2 Offline resident writes

Participation/completion actions may be queued locally when network is unavailable.

Each queued command needs:
- local command ID,
- created timestamp,
- entity ID,
- desired transition,
- retry count,
- idempotency key.

On reconnect:
1. send command,
2. backend validates current state,
3. backend applies idempotently,
4. client reconciles state.

## 16.3 Conflict rule

Server-authoritative state wins for safety/authorization fields.

Client may preserve an unsent user intent and show a recoverable conflict state instead of silently overwriting.

## 16.4 Offline weather copy

Never display cached weather as “current” without timestamp. Use copy equivalent to:
- “Data terakhir diperbarui …”
- “Mode offline / data tersimpan.”

---

# 17. Notification model

FCM is used for:
- new active task,
- reminder,
- operator verification needed,
- operator escalation,
- relevant task update/cancellation.

Do not send:
- misleading “official flood warning” phrasing,
- coercive participation messaging,
- sensitive resident details in notification preview.

Notification click routes to the exact task/entity.

---

# 18. Task template safety contract

Every task template must satisfy:

```text
template.id                immutable
template.version           immutable for historical campaign
template.title             controlled catalog content
template.coreInstruction   locked for RT operator
template.safetyInstruction locked for RT operator
template.category          controlled enum/reference
operator.deadline          editable
operator.locationNote      editable
operator.additionalNote    editable, length-limited
```

A task cannot become ACTIVE if:
- template disabled,
- safety instruction missing,
- deadline invalid,
- operator unauthorized,
- task uses arbitrary free-form core instruction.

Resident proposals never count as templates.

---

# 19. UI/UX rules

**SOURCE REQUIREMENT + UI derivation**

- Role identity must remain obvious.
- High-risk/administrative decisions require deliberate confirmation.
- Resident participation choices are symmetric and non-coercive.
- “Menunggu Verifikasi RT” must be visible when completion is not yet official.
- Offline state must be visible.
- Safety instructions are not hidden behind secondary UI when task is actionable.
- Emergency information is reachable from bottom navigation.
- Avoid information density that makes elderly/less technical residents unable to identify the primary action.
- Use Indonesian-language labels for the MVP unless a separate localization requirement is approved.

---

# 20. Error and degraded-mode requirements

## ERR-01 BMKG unavailable
- keep last valid snapshot,
- show stale timestamp,
- do not generate suggestions from malformed/unknown data.

## ERR-02 Notification delivery failure
- task remains valid in backend,
- operator dashboard can see campaign state,
- WhatsApp copy flow remains available.

## ERR-03 Offline mutation
- queue locally,
- show pending-sync state,
- retry idempotently.

## ERR-04 Invalid RT code
- do not reveal whether unrelated resident/RT records exist,
- return generic invalid/expired code response.

## ERR-05 Operator authorization mismatch
- reject backend command,
- do not rely only on UI hiding.

## ERR-06 Evidence upload failure
- completion can still proceed if evidence is optional,
- do not block all task completion solely due to photo failure.

---

# 21. Security requirements

SEC-01. Operator authorization is enforced server-side.  
SEC-02. Resident direct writes to protected Firestore records are denied unless an approved scoped mechanism is used.  
SEC-03. Join code is not treated as a global admin secret.  
SEC-04. Sensitive operations are idempotent.  
SEC-05. Logs avoid storing evidence images, credentials, or unnecessary PII.  
SEC-06. Secrets/API configuration are not committed to source control.  
SEC-07. Task activation is audited.  
SEC-08. Completion verification is audited.  
SEC-09. Evidence deletion is verifiable.  
SEC-10. App must tolerate replay/retry of offline commands without duplicating task state.

---

# 22. Acceptance test catalogue

## AT-001 — Threshold cannot auto-send
**Given** BMKG data crosses a configured rule  
**When** the evaluator runs  
**Then** a suggestion may exist  
**And** no ACTIVE task exists until operator confirmation.

## AT-002 — Unsafe free-form task blocked
**Given** an operator attempts to bypass catalog  
**Then** backend rejects activation.

## AT-003 — Immutable safety text
**Given** a safe template  
**When** operator edits deadline/location/note  
**Then** core safety instruction remains unchanged.

## AT-004 — Resident may decline
**Given** an ACTIVE task  
**When** resident chooses not to participate  
**Then** state becomes DECLINED  
**And** UI does not mark the resident as failed/bad.

## AT-005 — Completion requires verification
**Given** a resident submits completion  
**Then** state is PENDING_RT_VERIFICATION  
**Until** authorized operator verifies.

## AT-006 — Offline task read
**Given** task was synchronized  
**When** network is removed  
**Then** active task and safety instruction remain readable.

## AT-007 — Offline emergency info
Emergency contacts and assembly points remain readable without network.

## AT-008 — Weather stale marker
Cached weather always includes last update timestamp/offline indicator.

## AT-009 — No forbidden PII
Data model and UI contain no NIK/full address/resident GPS input.

## AT-010 — Evidence metadata stripping
Uploaded evidence has no retained location metadata.

## AT-011 — Evidence expiry
Evidence older than 30 days is physically deleted or marked failed with retry/alert until deletion succeeds.

## AT-012 — Resident proposal cannot activate
Proposal submission cannot produce an ACTIVE task directly.

## AT-013 — Official escalation
A problem categorized outside community capacity displays/configures official reporting route.

## AT-014 — Proxy status
Authorized operator can record status for a non-app resident.

## AT-015 — RT history persistence
Task history remains accessible after operator account changes.

---

# 23. Test strategy

## 23.1 Unit tests
Focus:
- task state transitions,
- threshold evaluation,
- safe-template validation,
- permission predicates,
- reminder scheduling,
- evidence expiry calculation,
- offline command idempotency.

## 23.2 Widget/UI tests
Focus:
- role-specific navigation,
- explicit confirmation,
- decline path,
- pending-verification state,
- offline banner,
- emergency page availability.

## 23.3 Firebase emulator integration tests
Focus:
- Firestore rules,
- Cloud Function authorization,
- task activation,
- resident scoped writes,
- reminder/escalation idempotency,
- evidence cleanup metadata.

## 23.4 End-to-end scenarios
Minimum:
1. weather -> suggestion -> RT approval -> resident join -> completion -> RT verify,
2. resident decline,
3. resident offline response -> reconnect sync,
4. resident proposal -> RT review -> catalog mapping,
5. vulnerable resident proxy/helper flow,
6. BMKG failure with stale cached data,
7. operator change with preserved RT history.

---

# 24. Implementation order

The implementation should be vertical-slice oriented.

## Phase 0 — Repository and foundations
- Flutter Android project.
- Firebase project environments.
- environment configuration.
- local persistence.
- CI/static analysis/test baseline.

## Phase 1 — Identity and RT context
- role selection,
- operator auth,
- resident RT-code session,
- RT-scoped authorization.

## Phase 2 — Safe task domain
- task template model,
- locked safety contract,
- RT task catalog,
- task draft/confirmation.

## Phase 3 — Resident task loop
- resident home/task list,
- join/decline,
- completion,
- RT verification,
- basic RT recap.

## Phase 4 — Weather
- BMKG sync,
- normalization,
- cached display,
- configurable rules,
- suggestion generation.

## Phase 5 — Automation
- FCM,
- reminders,
- non-response escalation,
- audit events.

## Phase 6 — Two-way coordination
- resident proposal,
- vulnerable resident records,
- helper assignment,
- proxy updates.

## Phase 7 — Offline and emergency
- locally cached active tasks,
- queued commands,
- emergency directory,
- assembly points,
- degraded-mode tests.

## Phase 8 — Evidence and data lifecycle
- metadata stripping,
- object storage,
- 30-day deletion,
- self/proxy deletion path.

## Phase 9 — History and pilot hardening
- historical RT view,
- handover persistence,
- security tests,
- accessibility/usability pass,
- pilot configuration.

---

# 25. Explicit open gaps and defaults

These are not defects in the proposal; they are implementation details not yet specified.

| Gap | Proposal says | Default for implementation |
|---|---|---|
| Weather threshold numbers | Detect threshold | Configurable data, no invented universal number |
| Reminder timing | Automatic reminders | Configuration, not hard-coded product truth |
| Escalation timing | Escalate non-response | Configuration |
| Resident identity | No account; RT code | Backend-mediated participant session |
| Photo binary storage | Optional proof, delete after 30 days | Firebase Cloud Storage extension |
| Pilot RT/kelurahan | Not fixed | Environment/pilot configuration |
| Emergency numbers | Mockups show examples | Configurable; mockup values are not production constants |
| Assembly points | Mockups show examples | Configurable and locally cached |
| Official reporting channel | SP4N-LAPOR!/BPBD/JAKI context | Area-aware configuration |
| Self-deletion without account | Residents can delete data | Same-device token; RT-assisted fallback |
| Exact safe catalog contents | Examples/principles shown | Seed only reviewed safe templates; no arbitrary execution task |

If an agent cannot implement a default without weakening a hard invariant, it must stop and request a decision rather than silently relax the invariant.

---

# 26. Definition of Done for the MVP

Guyub.id MVP is considered implementation-complete only when:

- Android APK builds successfully.
- Operator and resident entry paths work.
- No weather rule can bypass human confirmation.
- Task core/safety instructions are locked.
- Resident can join or decline.
- Completion requires RT verification.
- Reminder and escalation are idempotent.
- Resident proposals cannot become tasks without RT review.
- Vulnerable/non-app residents can be represented via proxy.
- Active task, last weather snapshot, emergency contacts, and assembly points work offline.
- No NIK/full address/precise GPS is required or persisted.
- Evidence photo location metadata is removed and retention is capped at 30 days.
- RT preparedness history is persistent beyond one operator account.
- BMKG attribution and update time are visible.
- Official-reporting redirection exists.
- Required acceptance tests pass.

---

# 27. Agent implementation directive

When an AI coding agent receives this specification, it must:

1. read this document fully before editing code;
2. treat `INV-*` requirements as hard safety constraints;
3. map every implementation task to one or more `FR-*` / `AT-*` requirements;
4. not add unrelated features;
5. not replace human confirmation with automation;
6. not introduce new resident PII;
7. not use mockup data as production constants;
8. keep source-derived behavior and engineering derivations distinguishable;
9. test state transitions and authorization at backend level, not only UI level;
10. report any unresolved contradiction before implementation.
