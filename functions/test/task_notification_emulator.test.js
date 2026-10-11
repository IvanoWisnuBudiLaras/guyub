const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { hashJoinCode, hashSessionToken } = require('../src/resident_session_service');
const { validateTaskNotificationPolicy } = require('../src/task_notification_policy');
const { FirestoreTaskNotificationRepository } = require('../src/firestore_task_notification_repository');
const { TaskNotificationService } = require('../src/task_notification_service');
const { FirebaseMessagingDeliveryAdapter } = require('../src/task_notification_delivery');
const { notificationEventId, residentRtRecipientHash } = require('../src/task_notification_id');
const { FirestoreTaskResponseRepository } = require('../src/firestore_task_response_repository');
const { TaskResponseService } = require('../src/task_response_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, functions: 5001 };
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const app = initializeApp({ projectId: PROJECT_ID }, `notification-emulator-${crypto.randomUUID()}`);
const firestore = getFirestore(app);

async function createAccount() {
  const suffix = crypto.randomUUID();
  const response = await fetch(`${AUTH_BASE}/accounts:signUp?key=fake-api-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: `task-notify-${suffix}@example.invalid`,
      password: 'test-password-123', returnSecureToken: true,
    }),
  });
  const result = await response.json();
  assert.equal(response.status, 200, JSON.stringify(result));
  return result;
}

async function callFunction(name, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`,
    { method: 'POST', headers, body: JSON.stringify({ data }) },
  );
  return { status: response.status, body: await response.json() };
}

function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}

function policyRecord(rtId, policyDocumentId) {
  return {
    policyDocumentId,
    policyId: 'community-readiness',
    version: 1,
    rtId,
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'approved-reviewer',
    reviewedAt: new Date(),
    reminderWindows: [
      { windowId: 'before-deadline-60', minutesBeforeDeadline: 60, cohort: 'UNRESPONDED' },
    ],
    escalation: {
      enabled: true,
      windowId: 'admin-before-deadline-30',
      minutesBeforeDeadline: 30,
      cohort: 'UNRESPONDED',
      minimumCohortSize: 1,
    },
    deliveryRetrySeconds: [60, 300],
  };
}

function taskTemplateSnapshot() {
  return {
    templateId: 'household-preparation',
    version: 1,
    title: 'Siapkan perlengkapan keluarga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting di tempat yang mudah dijangkau.',
    safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik basah.',
    estimatedDurationMinutes: 30,
  };
}

function token() { return `fcm-test-token-${crypto.randomUUID()}-abcdefghijklmnop`; }

test('notification outbox retries, isolates same-RT escalation recipients, and never blocks active task access', async (t) => {
  t.after(async () => app.delete());
  // Emulator tests share one Firestore instance. Remove only stale pending
  // lifecycle events left by earlier campaign fixtures so this test measures
  // the three events it creates below.
  for (const eventType of ['TASK_ACTIVATED', 'TASK_CANCELLED', 'TASK_CLOSED', 'TASK_VERIFICATION_NEEDED']) {
    const existing = await firestore.collection('task_notification_events')
      .where('eventType', '==', eventType).get();
    await Promise.all(existing.docs
      .filter((document) => document.data().status === 'PENDING')
      .map((document) => document.ref.delete()));
  }
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `notify-rt-a-${suffix}`;
  const rtB = `notify-rt-b-${suffix}`;
  const joinCodeA = `JA${suffix.slice(0, 14).toUpperCase()}`;
  const joinCodeB = `JB${suffix.slice(0, 14).toUpperCase()}`;
  const policyIdA = `policy-a-${suffix.slice(0, 20)}`;
  const policyIdB = `policy-b-${suffix.slice(0, 20)}`;
  const campaignId = crypto.randomBytes(20).toString('hex');
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  const operatorARef = firestore.collection('operators').doc(operatorA.localId);
  const operatorBRef = firestore.collection('operators').doc(operatorB.localId);
  const communityARef = firestore.collection('rt_communities').doc(rtA);
  const communityBRef = firestore.collection('rt_communities').doc(rtB);

  await Promise.all([
    operatorARef.set({ rtId: rtA, role: 'PENDAMPING_RT', active: true }),
    operatorBRef.set({ rtId: rtB, role: 'PENDAMPING_RT', active: true }),
    communityARef.set({
      displayName: `Community ${rtA}`, rtLabel: 'RT Test',
      joinCodeHash: hashJoinCode(joinCodeA), joinCodeActive: true,
      reminderPolicyId: policyIdA,
    }),
    communityBRef.set({
      displayName: `Community ${rtB}`, rtLabel: 'RT Test',
      joinCodeHash: hashJoinCode(joinCodeB), joinCodeActive: true,
      reminderPolicyId: policyIdB,
    }),
  ]);

  const policyA = policyRecord(rtA, policyIdA);
  const policyB = policyRecord(rtB, policyIdB);
  const validatedPolicyA = validateTaskNotificationPolicy(policyA, policyIdA, rtA);
  await Promise.all([
    firestore.collection('task_reminder_policies').doc(policyIdA).set(policyA),
    firestore.collection('task_reminder_policies').doc(policyIdB).set(policyB),
  ]);

  const createdResident = await callFunction('createResidentSession', {
    joinCode: joinCodeA,
    nickname: 'Warga Uji',
    requestId: crypto.randomBytes(32).toString('base64url'),
  });
  assert.equal(createdResident.status, 200, JSON.stringify(createdResident.body));
  const { sessionToken, residentId } = createdResident.body.result;
  const residentPushToken = token();
  const registeredResidentToken = await callFunction('registerResidentPushToken', {
    sessionToken, token: residentPushToken, platform: 'ANDROID',
  });
  assert.equal(registeredResidentToken.status, 200, JSON.stringify(registeredResidentToken.body));
  const createdResidentB = await callFunction('createResidentSession', {
    joinCode: joinCodeB,
    nickname: 'Warga RT lain',
    requestId: crypto.randomBytes(32).toString('base64url'),
  });
  assert.equal(createdResidentB.status, 200, JSON.stringify(createdResidentB.body));
  const residentPushTokenB = token();
  const registeredResidentTokenB = await callFunction('registerResidentPushToken', {
    sessionToken: createdResidentB.body.result.sessionToken,
    token: residentPushTokenB,
    platform: 'ANDROID',
  });
  assert.equal(registeredResidentTokenB.status, 200, JSON.stringify(registeredResidentTokenB.body));

  const operatorPushTokenA = token();
  const operatorPushTokenB = token();
  for (const [operator, pushToken] of [[operatorA, operatorPushTokenA], [operatorB, operatorPushTokenB]]) {
    const result = await callFunction('registerPendampingPushToken', {
      token: pushToken, platform: 'ANDROID',
    }, operator.idToken);
    assert.equal(result.status, 200, JSON.stringify(result.body));
  }

  const now = new Date();
  const deadline = new Date(now.getTime() + 60 * 60 * 1000);
  await firestore.collection('task_campaigns').doc(campaignId).set({
    campaignId,
    rtId: rtA,
    status: 'ACTIVE',
    activatedAt: now,
    deadline,
    locationReference: 'Titik kumpul RT',
    templateSnapshot: taskTemplateSnapshot(),
    notificationPolicyDocumentId: validatedPolicyA.policyDocumentId,
    notificationPolicyVersion: validatedPolicyA.version,
    notificationPolicyFingerprint: validatedPolicyA.fingerprint,
  });

  const failedTokens = new Set([residentPushToken]);
  const sentMessages = [];
  const messaging = {
    async send(message) {
      assert.ok(message.notification.title);
      assert.ok(message.notification.body);
      assert.match(message.data.taskId, /^[a-f0-9]{40}$/u);
      if (!['TASK_ACTIVATED', 'TASK_CANCELLED', 'TASK_CLOSED'].includes(message.data.eventType)) {
        assert.equal(message.data.taskId, campaignId);
      }
      assert.equal(message.notification.body.includes('resmi'), false);
      if (failedTokens.has(message.token)) throw new Error('transient delivery failure');
      sentMessages.push(message);
      return `accepted-${sentMessages.length}`;
    },
  };
  const repository = new FirestoreTaskNotificationRepository(firestore);
  const service = new TaskNotificationService(
    repository, new FirebaseMessagingDeliveryAdapter(messaging),
    { validateSession: async () => ({ residentId, communityId: rtA }) },
  );

  const reminderTime = new Date(deadline.getTime() - 60 * 60 * 1000);
  const policyScan = await repository.listEnabledPolicies();
  assert.ok(policyScan.some((item) => item.policyDocumentId === policyIdA));
  const campaignScan = await repository.listActiveCampaigns(rtA);
  assert.equal(campaignScan.some((item) => item.campaignId === campaignId), true);
  const residentScan = await repository.listResidentStates(rtA, campaignId);
  assert.equal(residentScan.length, 1);
  const firstReminder = await service.sendTaskReminders({ now: reminderTime });
  assert.equal(firstReminder.scheduled, 1);
  assert.equal(firstReminder.failed, 1);
  const reminderEvents = await firestore.collection('task_notification_events')
    .where('campaignId', '==', campaignId).where('eventType', '==', 'TASK_REMINDER').get();
  assert.equal(reminderEvents.size, 1);
  const reminder = reminderEvents.docs[0].data();
  assert.equal(reminder.status, 'PENDING');
  assert.equal(reminder.rtId, rtA);
  assert.equal(Object.hasOwn(reminder, 'residentId'), false);
  assert.equal(Object.hasOwn(reminder, 'token'), false);

  const taskResponseService = new TaskResponseService(
    new FirestoreTaskResponseRepository(firestore),
    { validateSession: async () => ({ residentId, communityId: rtA }) },
    { clock: () => reminderTime },
  );
  const accessibleTasks = await taskResponseService.listResidentActiveTasks({ sessionToken });
  assert.equal(accessibleTasks.items.some((task) => task.taskId === campaignId), true);
  assert.equal(accessibleTasks.items.find((task) => task.taskId === campaignId).status, 'ACTIVE');

  failedTokens.clear();
  const retryTime = new Date(reminderTime.getTime() + 61 * 1000);
  const reminderRetry = await service.sendTaskReminders({ now: retryTime });
  assert.equal(reminderRetry.scheduled, 0);
  assert.equal(reminderRetry.delivered, 1);
  assert.equal(sentMessages.length, 1);
  const duplicateWindowReplay = await service.sendTaskReminders({ now: retryTime });
  assert.equal(duplicateWindowReplay.scheduled, 0);
  assert.equal(duplicateWindowReplay.delivered, 0);

  const escalationTime = new Date(deadline.getTime() - 30 * 60 * 1000);
  const firstEscalation = await service.escalateUnrespondedTasks({ now: escalationTime });
  const escalationReplay = await service.escalateUnrespondedTasks({ now: escalationTime });
  assert.equal(firstEscalation.scheduled, 1);
  assert.equal(firstEscalation.delivered, 1);
  assert.equal(escalationReplay.scheduled, 0);
  assert.equal(escalationReplay.delivered, 0);
  assert.equal(sentMessages.length, 2);
  assert.equal(sentMessages[1].token, operatorPushTokenA);
  assert.notEqual(sentMessages[1].token, operatorPushTokenB);
  assert.equal(sentMessages[1].data.eventType, 'TASK_ESCALATION');

  const joined = await callFunction('recordResidentTaskResponse', {
    sessionToken,
    taskId: campaignId,
    choice: 'JOINED',
    commandId: crypto.randomBytes(32).toString('base64url'),
  });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  const verificationCommandId = crypto.randomBytes(32).toString('base64url');
  const completionPayload = {
    sessionToken,
    taskId: campaignId,
    note: null,
    commandId: verificationCommandId,
  };
  const completion = await callFunction('submitTaskCompletion', completionPayload);
  assert.equal(completion.status, 200, JSON.stringify(completion.body));
  assert.equal(completion.body.result.completionState, 'PENDING_RT_VERIFICATION');
  const completionReplay = await callFunction('submitTaskCompletion', completionPayload);
  assert.equal(completionReplay.status, 200, JSON.stringify(completionReplay.body));
  const verificationEvents = await firestore.collection('task_notification_events')
    .where('campaignId', '==', campaignId)
    .where('eventType', '==', 'TASK_VERIFICATION_NEEDED').get();
  assert.equal(verificationEvents.size, 1);
  const verificationEvent = verificationEvents.docs[0].data();
  assert.equal(verificationEvent.recipientKind, 'PENDAMPING_RT');
  assert.equal(verificationEvent.status, 'PENDING');
  assert.equal(Object.hasOwn(verificationEvent, 'residentId'), false);
  assert.equal(Object.hasOwn(verificationEvent, 'completionNote'), false);
  assert.equal(Object.hasOwn(verificationEvent, 'responseId'), false);
  assert.equal(JSON.stringify(verificationEvent).includes(verificationCommandId), false);
  const verificationAudit = await firestore.collection('task_notification_audit_events')
    .doc(verificationEvents.docs[0].id).get();
  assert.equal(Object.hasOwn(verificationAudit.data(), 'residentId'), false);
  const verificationDelivery = await service.sendCampaignTransitionNotifications({ now: new Date() });
  assert.deepEqual(verificationDelivery, { delivered: 1, failed: 0, skipped: 0 });
  assert.equal(sentMessages[2].token, operatorPushTokenA);
  assert.equal(sentMessages[2].data.eventType, 'TASK_VERIFICATION_NEEDED');
  assert.equal(sentMessages[2].data.taskId, campaignId);
  assert.notEqual(sentMessages[2].token, operatorPushTokenB);

  const lifecycleNotices = [
    { eventType: 'TASK_ACTIVATED', taskId: campaignId, status: 'ACTIVE', timeField: 'activatedAt' },
    { eventType: 'TASK_CANCELLED', taskId: crypto.randomBytes(20).toString('hex'),
      status: 'CANCELLED', timeField: 'cancelledAt' },
    { eventType: 'TASK_CLOSED', taskId: crypto.randomBytes(20).toString('hex'),
      status: 'CLOSED', timeField: 'closedAt' },
  ];
  for (const notice of lifecycleNotices) {
    const transitionAt = new Date(now.getTime() + 1000);
    if (notice.taskId !== campaignId) {
      await firestore.collection('task_campaigns').doc(notice.taskId).set({
        campaignId: notice.taskId,
        rtId: rtA,
        status: notice.status,
        activatedAt: now,
        [notice.timeField]: transitionAt,
        deadline,
        templateSnapshot: taskTemplateSnapshot(),
      });
    }
    const recipientHash = residentRtRecipientHash(rtA);
    const eventId = notificationEventId({
      rtId: rtA,
      campaignId: notice.taskId,
      eventType: notice.eventType,
      windowId: 'campaign-transition',
      recipientHash,
    });
    await firestore.collection('task_notification_events').doc(eventId).set({
      eventId,
      rtId: rtA,
      campaignId: notice.taskId,
      eventType: notice.eventType,
      policyDocumentId: null,
      policyVersion: null,
      policyFingerprint: null,
      windowId: 'campaign-transition',
      recipientKind: 'RESIDENTS_RT',
      recipientHash,
      deliveryRetrySeconds: [],
      status: 'PENDING',
      attemptCount: 0,
      nextAttemptAt: now,
      createdAt: now,
    });
  }
  const transitionDelivery = await service.sendCampaignTransitionNotifications({ now });
  assert.deepEqual(transitionDelivery, { delivered: 3, failed: 0, skipped: 0 });
  const transitionMessages = sentMessages.slice(-3);
  assert.deepEqual(transitionMessages.map((message) => message.data.eventType).sort(), [
    'TASK_ACTIVATED', 'TASK_CANCELLED', 'TASK_CLOSED',
  ]);
  assert.deepEqual(
    Object.fromEntries(transitionMessages.map((message) => [
      message.data.eventType, message.data.taskId,
    ])),
    Object.fromEntries(lifecycleNotices.map((notice) => [notice.eventType, notice.taskId])),
  );
  assert.ok(transitionMessages.every((message) => message.token === residentPushToken));
  assert.equal(transitionMessages.some((message) => message.token === residentPushTokenB), false);
  assert.ok(transitionMessages.every((message) =>
    !/peringatan banjir resmi|official flood warning/i.test(message.notification.body)));
  for (const notice of lifecycleNotices) {
    const eventId = notificationEventId({
      rtId: rtA,
      campaignId: notice.taskId,
      eventType: notice.eventType,
      windowId: 'campaign-transition',
      recipientHash: residentRtRecipientHash(rtA),
    });
    const storedEvent = await firestore.collection('task_notification_events').doc(eventId).get();
    assert.equal(storedEvent.data().status, 'SENT');
    assert.equal(Object.hasOwn(storedEvent.data(), 'residentId'), false);
    assert.equal(Object.hasOwn(storedEvent.data(), 'token'), false);
  }

  const responseId = require('../src/task_response_service')
    .responseDocumentId(rtA, campaignId, residentId);
  const responseSnapshot = await firestore.collection('task_responses').doc(responseId).get();
  assert.equal(responseSnapshot.exists, true);
  assert.equal(responseSnapshot.data().participationState, 'JOINED');
  assert.equal(responseSnapshot.data().completionState, 'PENDING_RT_VERIFICATION');
  const campaignSnapshot = await firestore.collection('task_campaigns').doc(campaignId).get();
  assert.equal(campaignSnapshot.data().status, 'ACTIVE');

  const auditSnapshot = await firestore.collection('task_notification_audit_events')
    .where('campaignId', '==', campaignId).get();
  assert.equal(auditSnapshot.size, 3);
  for (const auditDoc of auditSnapshot.docs) {
    const audit = auditDoc.data();
    assert.equal(audit.rtId, rtA);
    assert.equal(Object.hasOwn(audit, 'residentId'), false);
    assert.equal(Object.hasOwn(audit, 'recipientHash'), false);
    assert.equal(Object.hasOwn(audit, 'token'), false);
  }

  const auditAccessA = await callFunction(
    'listTaskNotificationAudit', { campaignId }, operatorA.idToken,
  );
  assert.equal(auditAccessA.status, 200, JSON.stringify(auditAccessA.body));
  assert.equal(auditAccessA.body.result.events.length, 3);
  const auditAccessB = await callFunction(
    'listTaskNotificationAudit', { campaignId }, operatorB.idToken,
  );
  assertError(auditAccessB, 'PERMISSION_DENIED');

  const sentBeforeDeclinedReplay = sentMessages.length;
  const declinedCampaignId = crypto.randomBytes(20).toString('hex');
  await firestore.collection('task_campaigns').doc(declinedCampaignId).set({
    campaignId: declinedCampaignId,
    rtId: rtA,
    status: 'ACTIVE',
    deadline,
    templateSnapshot: taskTemplateSnapshot(),
    notificationPolicyDocumentId: validatedPolicyA.policyDocumentId,
    notificationPolicyVersion: validatedPolicyA.version,
    notificationPolicyFingerprint: validatedPolicyA.fingerprint,
  });
  const { residentNotificationRecipientHash, tokenDocumentId } =
    require('../src/task_notification_id');
  const declinedEvent = await repository.createReminderEvent({
    rtId: rtA,
    campaignId: declinedCampaignId,
    policy: validatedPolicyA,
    window: validatedPolicyA.reminderWindows[0],
    residentId,
    recipientHash: residentNotificationRecipientHash(rtA, residentId),
    now: reminderTime,
  });
  assert.equal(declinedEvent.created, true);
  const declinedResponseId = require('../src/task_response_service')
    .responseDocumentId(rtA, declinedCampaignId, residentId);
  await firestore.collection('task_responses').doc(declinedResponseId).set({
    responseId: declinedResponseId,
    taskId: declinedCampaignId,
    rtId: rtA,
    residentId,
    participationState: 'DECLINED',
    completionState: 'NOT_SUBMITTED',
  });
  const declinedReplay = await service.sendTaskReminders({ now: reminderTime });
  assert.equal(declinedReplay.scheduled, 0);
  assert.equal(declinedReplay.skipped, 1);
  assert.equal(sentMessages.length, sentBeforeDeclinedReplay);
  const declinedOutboxEvent = await firestore.collection('task_notification_events')
    .doc(declinedEvent.eventId).get();
  assert.equal(declinedOutboxEvent.data().status, 'SKIPPED');
  const declinedResponse = await firestore.collection('task_responses').doc(declinedResponseId).get();
  assert.equal(declinedResponse.data().participationState, 'DECLINED');

  const residentTokenDocId = tokenDocumentId(residentPushToken);
  const residentTokenDoc = await firestore.collection('resident_push_tokens').doc(residentTokenDocId).get();
  assert.equal(residentTokenDoc.data().sessionIdHash, hashSessionToken(sessionToken));
  const directTokenAccess = await fetch(
    `http://127.0.0.1:8080/v1/projects/${PROJECT_ID}/databases/(default)/documents/resident_push_tokens/${residentTokenDocId}`,
  );
  assert.notEqual(directTokenAccess.status, 200);
  const revoked = await callFunction('revokeResidentSession', { sessionToken });
  assert.equal(revoked.status, 200, JSON.stringify(revoked.body));
  const clearedToken = await firestore.collection('resident_push_tokens').doc(residentTokenDocId).get();
  assert.equal(clearedToken.exists, false);
  const residentTokenDocIdB = require('../src/task_notification_id')
    .tokenDocumentId(residentPushTokenB);
  const revokedResidentB = await callFunction('revokeResidentSession', {
    sessionToken: createdResidentB.body.result.sessionToken,
  });
  assert.equal(revokedResidentB.status, 200, JSON.stringify(revokedResidentB.body));
  assert.equal((await firestore.collection('resident_push_tokens')
    .doc(residentTokenDocIdB).get()).exists, false);
});
