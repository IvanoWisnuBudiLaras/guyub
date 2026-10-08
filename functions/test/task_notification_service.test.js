const test = require('node:test');
const assert = require('node:assert/strict');
const { TaskNotificationService } = require('../src/task_notification_service');
const { notificationEventId, residentNotificationRecipientHash,
  pendampingRecipientHash } = require('../src/task_notification_id');

const RT_ID = 'rt-a';
const TASK_ID = 'a'.repeat(40);
const RESIDENT_ID = 'resident-a';
const NOW = new Date('2026-10-06T12:00:00.000Z');
const DEADLINE = new Date(NOW.getTime() + 60 * 60 * 1000);
const POLICY = {
  policyDocumentId: 'rt-a_policy_v1', policyId: 'policy', version: 1, rtId: RT_ID,
  enabled: true, reviewStatus: 'approved', fingerprint: 'f'.repeat(64),
  deliveryRetrySeconds: [30, 300],
  reminderWindows: [
    { windowId: 'before-60', minutesBeforeDeadline: 60, cohort: 'UNRESPONDED' },
    { windowId: 'before-30', minutesBeforeDeadline: 30, cohort: 'UNRESPONDED' },
  ],
  escalation: {
    enabled: true, windowId: 'escalate-before-30', minutesBeforeDeadline: 30,
    cohort: 'JOINED_NOT_SUBMITTED', minimumCohortSize: 1,
  },
};

class FakeRepository {
  constructor({ policy = POLICY, residents, tokens = ['resident-token'], operators = ['pendamping-token'] } = {}) {
    this.policy = policy;
    this.campaign = {
      campaignId: TASK_ID, rtId: RT_ID, status: 'ACTIVE', deadline: DEADLINE,
      notificationPolicyDocumentId: policy.policyDocumentId,
      notificationPolicyVersion: policy.version,
      notificationPolicyFingerprint: policy.fingerprint,
    };
    this.residents = residents ?? [{
      residentId: RESIDENT_ID,
      recipientHash: residentNotificationRecipientHash(RT_ID, RESIDENT_ID),
      response: null,
      valid: true,
    }];
    this.tokens = tokens;
    this.operators = operators;
    this.events = new Map();
    this.audit = new Map();
    this.sendings = [];
  }

  async listEnabledPolicies() { return [this.policy]; }
  async listActiveCampaigns(rtId) { return rtId === RT_ID ? [this.campaign] : []; }
  async listResidentStates(rtId, campaignId) {
    return rtId === RT_ID && campaignId === TASK_ID ? this.residents : [];
  }

  async createReminderEvent(input) {
    const eventId = notificationEventId({
      rtId: input.rtId, campaignId: input.campaignId,
      eventType: 'TASK_REMINDER', windowId: input.window.windowId,
      recipientHash: input.recipientHash,
    });
    if (this.events.has(eventId)) return { eventId, created: false };
    const event = {
      eventId, rtId: input.rtId, campaignId: input.campaignId,
      eventType: 'TASK_REMINDER', policyDocumentId: input.policy.policyDocumentId,
      policyVersion: input.policy.version, policyFingerprint: input.policy.fingerprint,
      windowId: input.window.windowId, cohort: input.window.cohort,
      recipientKind: 'RESIDENT', recipientHash: input.recipientHash,
      deliveryRetrySeconds: input.policy.deliveryRetrySeconds,
      status: 'PENDING', attemptCount: 0, nextAttemptAt: input.now,
    };
    this.events.set(eventId, event);
    this.audit.set(eventId, { eventType: event.eventType, windowId: event.windowId });
    return { eventId, created: true };
  }

  async createEscalationEvent(input) {
    const recipientHash = pendampingRecipientHash(input.rtId);
    const eventId = notificationEventId({
      rtId: input.rtId, campaignId: input.campaignId,
      eventType: 'TASK_ESCALATION', windowId: input.escalation.windowId, recipientHash,
    });
    if (this.events.has(eventId)) return { eventId, created: false };
    const event = {
      eventId, rtId: input.rtId, campaignId: input.campaignId,
      eventType: 'TASK_ESCALATION', policyDocumentId: input.policy.policyDocumentId,
      policyVersion: input.policy.version, policyFingerprint: input.policy.fingerprint,
      windowId: input.escalation.windowId, cohort: input.escalation.cohort,
      minimumCohortSize: input.escalation.minimumCohortSize,
      recipientKind: 'PENDAMPING_RT', recipientHash,
      deliveryRetrySeconds: input.policy.deliveryRetrySeconds,
      status: 'PENDING', attemptCount: 0, nextAttemptAt: input.now,
    };
    this.events.set(eventId, event);
    this.audit.set(eventId, { eventType: event.eventType, windowId: event.windowId });
    return { eventId, created: true };
  }

  async listDueEvents(type, now) {
    return [...this.events.values()].filter((event) => event.eventType === type &&
      event.status === 'PENDING' && event.nextAttemptAt <= now);
  }

  async claimEvent({ eventId, eventType, now, leaseId }) {
    const event = this.events.get(eventId);
    if (!event || event.eventType !== eventType || event.status !== 'PENDING' ||
        event.nextAttemptAt > now || (event.leaseUntil && event.leaseUntil > now)) return null;
    event.attemptCount += 1;
    event.leaseId = leaseId;
    event.leaseUntil = new Date(now.getTime() + 120_000);
    return { ...event };
  }

  async resolveDeliveryTargets(event, now) {
    if (this.campaign.status !== 'ACTIVE' || now >= this.campaign.deadline) {
      return { valid: false, targets: [] };
    }
    if (event.recipientKind === 'RESIDENT') {
      const resident = this.residents.find((item) => item.recipientHash === event.recipientHash);
      if (!resident?.valid) return { valid: false, targets: [] };
      return { valid: true, targets: this.tokens.map((token) => ({
        token, tokenId: '1'.repeat(64), tokenKind: 'RESIDENT',
      })) };
    }
    const eligible = this.residents.filter((resident) => resident.valid &&
      resident.response?.participationState === 'JOINED' &&
      resident.response?.completionState === 'NOT_SUBMITTED');
    if (eligible.length < event.minimumCohortSize) return { valid: false, targets: [] };
    return { valid: true, targets: this.operators.map((token) => ({
      token, tokenId: '2'.repeat(64), tokenKind: 'OPERATOR',
    })) };
  }

  async markEventSent({ eventId, leaseId, now }) {
    const event = this.events.get(eventId);
    if (event?.leaseId !== leaseId) return;
    event.status = 'SENT';
    event.sentAt = now;
    delete event.leaseId;
    delete event.leaseUntil;
  }

  async markEventSkipped({ eventId, leaseId, reason }) {
    const event = this.events.get(eventId);
    if (event?.leaseId !== leaseId) return;
    event.status = 'SKIPPED';
    event.skipReason = reason;
  }

  async markEventAttemptFailed({ eventId, leaseId, now, errorCode }) {
    const event = this.events.get(eventId);
    if (event?.leaseId !== leaseId) return;
    event.lastErrorCode = errorCode;
    const delay = event.deliveryRetrySeconds[event.attemptCount - 1];
    if (delay == null) event.status = 'FAILED';
    else event.nextAttemptAt = new Date(now.getTime() + delay * 1000);
    delete event.leaseId;
    delete event.leaseUntil;
  }

  async disableToken() {}
  async listAuditEvents() { return [...this.audit.values()]; }
}

function createService(repository, sender) {
  return new TaskNotificationService(repository, sender, { validateSession: async () => ({}) }, {
    clock: () => NOW,
    idFactory: (() => { let id = 0; return () => `claim-${++id}`; })(),
  });
}

test('scheduler retry produces one reminder event and one eventual accepted notice', async () => {
  const repository = new FakeRepository();
  let calls = 0;
  const delivery = { async send({ event }) {
    calls += 1;
    if (calls === 1) throw new Error('transient FCM outage');
    repository.sendings.push(event.eventId);
  } };
  const service = createService(repository, delivery);
  const first = await service.sendTaskReminders({ now: NOW });
  assert.deepEqual(first, { scheduled: 1, delivered: 0, failed: 1, skipped: 0 });
  const event = [...repository.events.values()][0];
  assert.equal(event.status, 'PENDING');
  assert.equal(repository.events.size, 1);
  const retryAt = event.nextAttemptAt;
  const second = await service.sendTaskReminders({ now: new Date(retryAt.getTime() + 1) });
  assert.equal(second.scheduled, 0);
  assert.equal(second.delivered, 1);
  assert.equal(repository.events.size, 1);
  assert.equal(repository.audit.size, 1);
  assert.equal(repository.sendings.length, 1);
});

test('same reminder policy window cannot duplicate and a later configured window can run', async () => {
  const repository = new FakeRepository();
  const delivery = { async send({ event }) { repository.sendings.push(event.eventId); } };
  const service = createService(repository, delivery);
  const firstNow = new Date(DEADLINE.getTime() - 60 * 60 * 1000);
  await service.sendTaskReminders({ now: firstNow });
  await service.sendTaskReminders({ now: new Date(firstNow.getTime() + 1000) });
  assert.equal(repository.events.size, 1);
  const laterNow = new Date(DEADLINE.getTime() - 30 * 60 * 1000);
  const later = await service.sendTaskReminders({ now: laterNow });
  assert.equal(later.scheduled, 1);
  assert.equal(repository.events.size, 2);
  assert.equal(repository.audit.size, 2);
});

test('escalation is replay-safe and does not alter resident participation or task state', async () => {
  const resident = {
    residentId: RESIDENT_ID,
    recipientHash: residentNotificationRecipientHash(RT_ID, RESIDENT_ID),
    response: { participationState: 'JOINED', completionState: 'NOT_SUBMITTED' },
    valid: true,
  };
  const repository = new FakeRepository({ residents: [resident] });
  const delivery = { async send({ event }) { repository.sendings.push(event.eventId); } };
  const service = createService(repository, delivery);
  const dueAt = new Date(DEADLINE.getTime() - 30 * 60 * 1000);
  const first = await service.escalateUnrespondedTasks({ now: dueAt });
  const replay = await service.escalateUnrespondedTasks({ now: dueAt });
  assert.equal(first.scheduled, 1);
  assert.equal(first.delivered, 1);
  assert.equal(replay.scheduled, 0);
  assert.equal(replay.delivered, 0);
  assert.equal(repository.events.size, 1);
  assert.equal(repository.audit.size, 1);
  assert.equal(repository.sendings.length, 1);
  assert.deepEqual(resident.response, {
    participationState: 'JOINED', completionState: 'NOT_SUBMITTED',
  });
  assert.equal(repository.campaign.status, 'ACTIVE');
});

test('declined residents never receive a reminder', async () => {
  const resident = {
    residentId: RESIDENT_ID,
    recipientHash: residentNotificationRecipientHash(RT_ID, RESIDENT_ID),
    response: { participationState: 'DECLINED', completionState: 'NOT_SUBMITTED' },
    valid: true,
  };
  const repository = new FakeRepository({ residents: [resident] });
  const service = createService(repository, { async send() { assert.fail('must not send'); } });
  const result = await service.sendTaskReminders({ now: NOW });
  assert.equal(result.scheduled, 0);
  assert.equal(repository.events.size, 0);
});

test('one-minute reminder window is delivered during its deadline interval and remains idempotent', async () => {
  const policy = {
    ...POLICY,
    reminderWindows: [{
      windowId: 'before-1', minutesBeforeDeadline: 1, cohort: 'UNRESPONDED',
    }],
  };
  const repository = new FakeRepository({ policy });
  const delivery = { async send({ event }) {
    repository.sendings.push(event.eventId);
  } };
  const service = createService(repository, delivery);
  const windowStart = new Date(DEADLINE.getTime() - 60_000);

  const early = await service.sendTaskReminders({ now: new Date(windowStart.getTime() - 1) });
  assert.equal(early.scheduled, 0);
  assert.equal(repository.events.size, 0);

  const first = await service.sendTaskReminders({ now: new Date(windowStart.getTime() + 15_000) });
  const replay = await service.sendTaskReminders({ now: new Date(windowStart.getTime() + 30_000) });
  assert.equal(first.scheduled, 1);
  assert.equal(first.delivered, 1);
  assert.equal(replay.scheduled, 0);
  assert.equal(replay.delivered, 0);
  assert.equal(repository.events.size, 1);
  assert.equal(repository.audit.size, 1);
  assert.equal(repository.sendings.length, 1);
});
