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
      assert.equal(message.data.taskId, campaignId);
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

  const responseId = require('../src/task_response_service')
    .responseDocumentId(rtA, campaignId, residentId);
  const responseSnapshot = await firestore.collection('task_responses').doc(responseId).get();
  assert.equal(responseSnapshot.exists, false);
  const campaignSnapshot = await firestore.collection('task_campaigns').doc(campaignId).get();
  assert.equal(campaignSnapshot.data().status, 'ACTIVE');

  const auditSnapshot = await firestore.collection('task_notification_audit_events')
    .where('campaignId', '==', campaignId).get();
  assert.equal(auditSnapshot.size, 2);
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
  assert.equal(auditAccessA.body.result.events.length, 2);
  const auditAccessB = await callFunction(
    'listTaskNotificationAudit', { campaignId }, operatorB.idToken,
  );
  assertError(auditAccessB, 'PERMISSION_DENIED');

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
  assert.equal(sentMessages.length, 2);
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
});
