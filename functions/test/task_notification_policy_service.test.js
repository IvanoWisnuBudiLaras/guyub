const test = require('node:test');
const assert = require('node:assert/strict');
const {
  TaskNotificationPolicyError,
  cohortMatches,
  validateTaskNotificationPolicy,
} = require('../src/task_notification_policy');
const { notificationCopy } = require('../src/task_notification_delivery');

const REVIEWED_AT = new Date('2026-10-06T12:00:00.000Z');
const POLICY = {
  policyDocumentId: 'rt-a_flood-readiness_v3',
  policyId: 'flood-readiness',
  version: 3,
  rtId: 'rt-a',
  enabled: true,
  reviewStatus: 'approved',
  reviewedBy: 'config-reviewer',
  reviewedAt: REVIEWED_AT,
  reminderWindows: [
    { windowId: 'before-deadline-60', minutesBeforeDeadline: 60, cohort: 'UNRESPONDED' },
    { windowId: 'before-deadline-180', minutesBeforeDeadline: 180, cohort: 'JOINED_NOT_SUBMITTED' },
  ],
  escalation: {
    enabled: true,
    windowId: 'admin-review-before-deadline',
    minutesBeforeDeadline: 30,
    cohort: 'UNRESPONDED_OR_JOINED_NOT_SUBMITTED',
    minimumCohortSize: 2,
  },
  deliveryRetrySeconds: [60, 300, 1800],
};

test('reviewed notification policy is versioned and keeps all timing values configurable', () => {
  const policy = validateTaskNotificationPolicy(POLICY, POLICY.policyDocumentId, 'rt-a');
  assert.equal(policy.version, 3);
  assert.equal(policy.reminderWindows[0].windowId, 'before-deadline-180');
  assert.equal(policy.reminderWindows[1].minutesBeforeDeadline, 60);
  assert.equal(policy.escalation.minimumCohortSize, 2);
  assert.equal(policy.fingerprint.length, 64);
  assert.throws(() => validateTaskNotificationPolicy(POLICY, POLICY.policyDocumentId, 'rt-b'),
    TaskNotificationPolicyError);
});

test('unreviewed or malformed policy cannot schedule delivery', () => {
  assert.throws(() => validateTaskNotificationPolicy({
    ...POLICY,
    reviewStatus: 'pending',
  }, POLICY.policyDocumentId, 'rt-a'), TaskNotificationPolicyError);
  assert.throws(() => validateTaskNotificationPolicy({
    ...POLICY,
    reminderWindows: [
      POLICY.reminderWindows[0],
      { ...POLICY.reminderWindows[1], windowId: POLICY.reminderWindows[0].windowId },
    ],
  }, POLICY.policyDocumentId, 'rt-a'), TaskNotificationPolicyError);
});

test('configured reminder cohorts never include declined or completed residents', () => {
  assert.equal(cohortMatches('UNRESPONDED', null), true);
  assert.equal(cohortMatches('UNRESPONDED', { participationState: 'DECLINED' }), false);
  assert.equal(cohortMatches('JOINED_NOT_SUBMITTED', {
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  }), true);
  assert.equal(cohortMatches('JOINED_NOT_SUBMITTED', {
    participationState: 'JOINED', completionState: 'PENDING_RT_VERIFICATION',
  }), false);
});

test('all task notification copy is generic, safe, and never an official warning', () => {
  for (const eventType of [
    'TASK_REMINDER', 'TASK_ESCALATION', 'TASK_ACTIVATED', 'TASK_CANCELLED', 'TASK_CLOSED',
    'TASK_VERIFICATION_NEEDED',
  ]) {
    const copy = notificationCopy(eventType);
    const text = `${copy.title} ${copy.body}`.toLowerCase();
    assert.doesNotMatch(text, /peringatan resmi|official flood warning|peringatan banjir resmi/u);
    assert.doesNotMatch(text, /nama warga|alamat|nomor rumah|diagnosis/u);
    assert.match(text, /sukarela|administratif|perubahan tugas|tinjauan/u);
  }
  assert.match(notificationCopy('TASK_ACTIVATED').body, /sukarela/u);
});
