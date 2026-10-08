const crypto = require('node:crypto');

const RT_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/u;
const POLICY_ID_PATTERN = /^[A-Za-z0-9_-]{1,120}$/u;
const WINDOW_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/u;
const POLICY_COHORTS = new Set([
  'UNRESPONDED',
  'JOINED_NOT_SUBMITTED',
  'UNRESPONDED_OR_JOINED_NOT_SUBMITTED',
]);
const MAX_POLICY_WINDOWS = 10;
const MAX_POLICY_OFFSET_MINUTES = 525600;
const MAX_ELIGIBLE_RESIDENTS = 500;
const MAX_RETRY_DELAYS = 8;
const MAX_RETRY_DELAY_SECONDS = 86400;

class TaskNotificationPolicyError extends Error {
  constructor(code, message = 'Kebijakan notifikasi tidak valid.') {
    super(message);
    this.name = 'TaskNotificationPolicyError';
    this.code = code;
  }
}

function toDate(value) {
  let date;
  if (value instanceof Date) date = value;
  else if (value && typeof value.toDate === 'function') {
    try { date = value.toDate(); } catch (_) { return null; }
  } else if (typeof value === 'string') date = new Date(value);
  else return null;
  return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
}

function policyShape(policy, docId, expectedRtId) {
  if (!policy || policy.enabled !== true || policy.reviewStatus !== 'approved' ||
      policy.rtId !== expectedRtId || !RT_ID_PATTERN.test(expectedRtId || '') ||
      typeof policy.policyId !== 'string' || !POLICY_ID_PATTERN.test(policy.policyId) ||
      !Number.isSafeInteger(policy.version) || policy.version < 1 ||
      typeof docId !== 'string' || docId.length === 0 || policy.policyDocumentId !== docId ||
      typeof policy.reviewedBy !== 'string' || policy.reviewedBy.trim().length === 0 ||
      !toDate(policy.reviewedAt) || !Array.isArray(policy.reminderWindows) ||
      policy.reminderWindows.length > MAX_POLICY_WINDOWS ||
      !Array.isArray(policy.deliveryRetrySeconds) ||
      policy.deliveryRetrySeconds.length > MAX_RETRY_DELAYS) {
    throw new TaskNotificationPolicyError('failed-precondition');
  }

  const windowIds = new Set();
  const offsets = new Set();
  const reminderWindows = policy.reminderWindows.map((window) => {
    if (!window || typeof window.windowId !== 'string' ||
        !WINDOW_ID_PATTERN.test(window.windowId) || windowIds.has(window.windowId) ||
        !Number.isSafeInteger(window.minutesBeforeDeadline) ||
        window.minutesBeforeDeadline < 1 ||
        window.minutesBeforeDeadline > MAX_POLICY_OFFSET_MINUTES ||
        !POLICY_COHORTS.has(window.cohort) || offsets.has(window.minutesBeforeDeadline)) {
      throw new TaskNotificationPolicyError('failed-precondition');
    }
    windowIds.add(window.windowId);
    offsets.add(window.minutesBeforeDeadline);
    return {
      windowId: window.windowId,
      minutesBeforeDeadline: window.minutesBeforeDeadline,
      cohort: window.cohort,
    };
  }).sort((left, right) => right.minutesBeforeDeadline - left.minutesBeforeDeadline);

  let escalation = null;
  if (policy.escalation != null && policy.escalation.enabled === true) {
    const value = policy.escalation;
    if (typeof value.windowId !== 'string' || !WINDOW_ID_PATTERN.test(value.windowId) ||
        !Number.isSafeInteger(value.minutesBeforeDeadline) ||
        value.minutesBeforeDeadline < 1 ||
        value.minutesBeforeDeadline > MAX_POLICY_OFFSET_MINUTES ||
        !POLICY_COHORTS.has(value.cohort) ||
        !Number.isSafeInteger(value.minimumCohortSize) ||
        value.minimumCohortSize < 1 || value.minimumCohortSize > MAX_ELIGIBLE_RESIDENTS) {
      throw new TaskNotificationPolicyError('failed-precondition');
    }
    escalation = {
      enabled: true,
      windowId: value.windowId,
      minutesBeforeDeadline: value.minutesBeforeDeadline,
      cohort: value.cohort,
      minimumCohortSize: value.minimumCohortSize,
    };
  } else if (policy.escalation != null && policy.escalation.enabled !== false) {
    throw new TaskNotificationPolicyError('failed-precondition');
  } else {
    escalation = { enabled: false };
  }

  const deliveryRetrySeconds = [...policy.deliveryRetrySeconds];
  let previousDelay = 0;
  for (const delay of deliveryRetrySeconds) {
    if (!Number.isSafeInteger(delay) || delay <= previousDelay ||
        delay > MAX_RETRY_DELAY_SECONDS) {
      throw new TaskNotificationPolicyError('failed-precondition');
    }
    previousDelay = delay;
  }

  return {
    policyDocumentId: docId,
    policyId: policy.policyId,
    version: policy.version,
    rtId: policy.rtId,
    enabled: true,
    reviewStatus: 'approved',
    reminderWindows,
    escalation,
    deliveryRetrySeconds,
    reviewedBy: policy.reviewedBy,
    reviewedAt: toDate(policy.reviewedAt),
  };
}

function policyFingerprint(policy) {
  const canonical = JSON.stringify([
    policy.policyDocumentId,
    policy.policyId,
    policy.version,
    policy.rtId,
    policy.reviewStatus,
    policy.reminderWindows.map((window) => [
      window.windowId, window.minutesBeforeDeadline, window.cohort,
    ]),
    policy.escalation.enabled
      ? [true, policy.escalation.windowId, policy.escalation.minutesBeforeDeadline,
        policy.escalation.cohort, policy.escalation.minimumCohortSize]
      : [false],
    policy.deliveryRetrySeconds,
  ]);
  return crypto.createHash('sha256').update(canonical, 'utf8').digest('hex');
}

function validateTaskNotificationPolicy(record, docId, expectedRtId) {
  const policy = policyShape(record, docId, expectedRtId);
  return { ...policy, fingerprint: policyFingerprint(policy) };
}

function cohortMatches(cohort, response) {
  const unresponded = response == null || response.participationState === 'UNRESPONDED';
  const joinedIncomplete = response?.participationState === 'JOINED' &&
    response.completionState === 'NOT_SUBMITTED';
  if (cohort === 'UNRESPONDED') return unresponded;
  if (cohort === 'JOINED_NOT_SUBMITTED') return joinedIncomplete;
  if (cohort === 'UNRESPONDED_OR_JOINED_NOT_SUBMITTED') {
    return unresponded || joinedIncomplete;
  }
  return false;
}

module.exports = {
  MAX_ELIGIBLE_RESIDENTS,
  MAX_POLICY_OFFSET_MINUTES,
  POLICY_COHORTS,
  TaskNotificationPolicyError,
  cohortMatches,
  policyFingerprint,
  toDate,
  validateTaskNotificationPolicy,
};
