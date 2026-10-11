const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const {
  TaskCampaignService,
  approvedTemplateFromRecord,
} = require('../src/task_campaign_service');

const NOW = new Date('2026-10-04T12:00:00.000Z');
const TEMPLATE = {
  templateId: 'household_ready',
  version: 1,
  title: 'Persiapan rumah tangga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting dalam wadah yang mudah dijangkau.',
  safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik yang basah.',
  estimatedDurationMinutes: 30,
  enabled: true,
  reviewStatus: 'approved',
  reviewedBy: 'trusted-reviewer',
  reviewedAt: NOW,
};
const AUTH = { operatorUid: 'operator-a', signInProvider: 'password' };
const REQUEST_ID = 'r'.repeat(40);
const COMMAND_ID = 'c'.repeat(40);

class FakeRepository {
  constructor() {
    this.templates = [TEMPLATE];
    this.drafts = [];
    this.activations = [];
    this.cancellations = [];
    this.closures = [];
    this.lifecycleRequests = [];
    this.lifecycleEvents = [];
    this.activeCampaigns = [];
    this.historyRequests = [];
    this.historyPage = { tasks: [], nextCursor: null };
  }
  async listApprovedTemplates() {
    return this.templates.map((record) => approvedTemplateFromRecord(
      record,
      record.templateId,
      record.version,
    )).filter(Boolean);
  }
  async createDraft(input) {
    this.drafts.push(input);
    return {
      campaignId: input.campaignId,
      rtId: 'rt-a',
      templateSnapshot: {
        templateId: TEMPLATE.templateId,
        version: TEMPLATE.version,
        title: TEMPLATE.title,
        category: TEMPLATE.category,
        coreInstruction: TEMPLATE.coreInstruction,
        safetyInstruction: TEMPLATE.safetyInstruction,
        estimatedDurationMinutes: TEMPLATE.estimatedDurationMinutes,
      },
      deadline: input.deadline,
      locationReference: input.locationReference,
      status: 'DRAFT',
      createdAt: input.now,
    };
  }
  async activateCampaign(input) {
    this.activations.push(input);
    return {
      campaignId: input.campaignId,
      rtId: 'rt-a',
      templateSnapshot: {},
      deadline: new Date('2026-10-05T00:00:00.000Z'),
      status: 'ACTIVE',
      activatedAt: input.now,
    };
  }
  async listActiveCampaigns() {
    return this.activeCampaigns;
  }
  async listRtTaskHistory(operatorUid, input) {
    this.historyRequests.push({ operatorUid, ...input });
    return this.historyPage;
  }
  async closeCampaign(input) {
    this.closures.push(input);
    return { campaignId: input.taskId, status: 'CLOSED' };
  }
  async listTaskLifecycleEvents(operatorUid, taskId) {
    this.lifecycleRequests.push({ operatorUid, taskId });
    return this.lifecycleEvents;
  }
  async cancelCampaign(input) {
    this.cancellations.push(input);
    return { campaignId: input.taskId, status: 'CANCELLED' };
  }
}

function setup() {
  const repository = new FakeRepository();
  const service = new TaskCampaignService(repository, { clock: () => new Date(NOW) });
  return { repository, service };
}

function draftPayload(overrides = {}) {
  return {
    templateId: TEMPLATE.templateId,
    version: TEMPLATE.version,
    deadline: '2026-10-05T12:00:00.000Z',
    locationReference: 'COMMUNITY_GENERAL_AREA',
    requestId: REQUEST_ID,
    ...overrides,
  };
}

test('approved templates require a reviewed, enabled version and locked safety text', () => {
  assert.ok(approvedTemplateFromRecord(TEMPLATE, TEMPLATE.templateId, TEMPLATE.version));
  assert.equal(approvedTemplateFromRecord(
    { ...TEMPLATE, enabled: false }, TEMPLATE.templateId, TEMPLATE.version,
  ), null);
  assert.equal(approvedTemplateFromRecord(
    { ...TEMPLATE, reviewStatus: 'draft' }, TEMPLATE.templateId, TEMPLATE.version,
  ), null);
  assert.equal(approvedTemplateFromRecord(
    { ...TEMPLATE, safetyInstruction: ' ' }, TEMPLATE.templateId, TEMPLATE.version,
  ), null);
  assert.equal(approvedTemplateFromRecord(
    { ...TEMPLATE, category: 'UNCONTROLLED' }, TEMPLATE.templateId, TEMPLATE.version,
  ), null);
});

test('catalog access and draft creation require a password-authenticated operator', async () => {
  const { repository, service } = setup();
  await assert.rejects(service.listApprovedTemplates({
    operatorUid: 'resident', signInProvider: 'anonymous',
  }), { code: 'permission-denied' });
  await assert.rejects(service.createDraft({
    operatorUid: 'resident', signInProvider: 'anonymous',
  }, draftPayload()), { code: 'permission-denied' });
  assert.equal(repository.drafts.length, 0);
});

test('catalog exposes only approved locked fields and hides review metadata', async () => {
  const { service } = setup();
  const templates = await service.listApprovedTemplates(AUTH);
  assert.equal(templates.length, 1);
  assert.deepEqual(templates[0], {
    templateId: TEMPLATE.templateId,
    version: TEMPLATE.version,
    title: TEMPLATE.title,
    category: TEMPLATE.category,
    coreInstruction: TEMPLATE.coreInstruction,
    safetyInstruction: TEMPLATE.safetyInstruction,
    estimatedDurationMinutes: TEMPLATE.estimatedDurationMinutes,
  });
});

test('draft request accepts only safe editable slots and is bound to a stable request id', async () => {
  const { repository, service } = setup();
  const first = await service.createDraft(AUTH, draftPayload());
  const retry = await service.createDraft(AUTH, draftPayload());
  assert.equal(first.campaignId, retry.campaignId);
  assert.equal(first.status, 'DRAFT');
  assert.equal(first.locationReference, 'COMMUNITY_GENERAL_AREA');
  assert.equal('additionalNote' in first, false);
  assert.equal(repository.drafts[0].operatorUid, AUTH.operatorUid);
  assert.equal(repository.drafts[0].templateId, TEMPLATE.templateId);
  assert.equal(repository.drafts[0].requestFingerprint, repository.drafts[1].requestFingerprint);
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    coreInstruction: 'Unsafe client-authored task text',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    safetyInstruction: 'Forged safety content',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    locationReference: '-6.123456, 106.123456',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    locationReference: 'Masuk ke saluran air untuk membersihkan sampah',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    additionalNote: 'Masuk ke saluran air untuk membersihkan sampah',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    additionalNote: 'NIK 1234567890123456',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    additionalNote: 'Hubungi 081234567890',
  })), { code: 'invalid-argument' });
  await assert.rejects(service.createDraft(AUTH, draftPayload({
    deadline: '2026-10-04T11:59:00.000Z',
  })), { code: 'invalid-argument' });
  assert.equal(repository.drafts.length, 2);
});

test('activation accepts only a campaign id and a stable command id', async () => {
  const { repository, service } = setup();
  const draft = await service.createDraft(AUTH, draftPayload());
  const activated = await service.activateCampaign(AUTH, {
    campaignId: draft.campaignId,
    commandId: COMMAND_ID,
  });
  assert.equal(activated.status, 'ACTIVE');
  assert.equal(repository.activations[0].operatorUid, AUTH.operatorUid);
  await assert.rejects(service.activateCampaign(AUTH, {
    campaignId: draft.campaignId,
    commandId: COMMAND_ID,
    rtId: 'rt-other',
  }), { code: 'invalid-argument' });
  await assert.rejects(service.activateCampaign(AUTH, {
    campaignId: draft.campaignId,
    commandId: COMMAND_ID,
    coreInstruction: 'replace the immutable instruction',
  }), { code: 'invalid-argument' });
});


test('active campaign listing is operator-authenticated and exposes only bounded task fields', async () => {
  const { repository, service } = setup();
  repository.activeCampaigns = [{
    campaignId: 'a'.repeat(40),
    rtId: 'rt-a',
    templateSnapshot: {
      templateId: TEMPLATE.templateId,
      version: TEMPLATE.version,
      title: TEMPLATE.title,
      category: TEMPLATE.category,
      coreInstruction: TEMPLATE.coreInstruction,
      safetyInstruction: TEMPLATE.safetyInstruction,
    },
    deadline: NOW,
    locationReference: 'HOUSEHOLD',
  }];
  const result = await service.listActiveTaskCampaigns(AUTH, {});
  assert.deepEqual(result, {
    tasks: [{
      taskId: 'a'.repeat(40),
      templateSnapshot: repository.activeCampaigns[0].templateSnapshot,
      deadline: NOW.toISOString(),
      locationReference: 'HOUSEHOLD',
    }],
  });
  await assert.rejects(service.listActiveTaskCampaigns({
    operatorUid: AUTH.operatorUid, signInProvider: 'anonymous',
  }, {}), { code: 'permission-denied' });
  await assert.rejects(service.listActiveTaskCampaigns(AUTH, { rtId: 'rt-b' }), {
    code: 'invalid-argument',
  });
});

test('RT task history validates input, returns bounded records, and uses opaque cursors', async () => {
  const { repository, service } = setup();
  const seconds = Math.floor(NOW.getTime() / 1000);
  const cursor = { seconds, nanoseconds: 0, campaignId: 'a'.repeat(40) };
  repository.historyPage = {
    tasks: [{
      campaignId: 'a'.repeat(40),
      templateSnapshot: {
        templateId: TEMPLATE.templateId,
        version: TEMPLATE.version,
        title: TEMPLATE.title,
        category: TEMPLATE.category,
        coreInstruction: TEMPLATE.coreInstruction,
        safetyInstruction: TEMPLATE.safetyInstruction,
      },
      deadline: NOW,
      locationReference: null,
      status: 'ACTIVE',
      activatedAt: NOW,
      cancelledAt: null,
      closedAt: null,
    }],
    nextCursor: cursor,
  };

  const result = await service.listRtTaskHistory(AUTH, { pageSize: 2 });
  assert.deepEqual(Object.keys(result).sort(), ['nextCursor', 'tasks']);
  assert.deepEqual(Object.keys(result.tasks[0]).sort(), [
    'activatedAt', 'cancelledAt', 'closedAt', 'deadline', 'locationReference', 'status',
    'taskId', 'templateSnapshot',
  ]);
  assert.deepEqual(result.tasks[0], {
    taskId: 'a'.repeat(40),
    templateSnapshot: repository.historyPage.tasks[0].templateSnapshot,
    deadline: NOW.toISOString(),
    locationReference: null,
    status: 'ACTIVE',
    activatedAt: NOW.toISOString(),
    cancelledAt: null,
    closedAt: null,
  });
  assert.match(result.nextCursor, /^[A-Za-z0-9_-]{1,256}$/u);
  assert.deepEqual(JSON.parse(Buffer.from(result.nextCursor, 'base64url').toString('utf8')), {
    v: 1,
    seconds,
    nanoseconds: 0,
    campaignId: 'a'.repeat(40),
  });
  assert.deepEqual(repository.historyRequests[0], {
    operatorUid: AUTH.operatorUid,
    pageSize: 2,
    cursor: null,
  });

  await service.listRtTaskHistory(AUTH, { cursor: result.nextCursor });
  assert.deepEqual(repository.historyRequests[1], {
    operatorUid: AUTH.operatorUid,
    pageSize: 25,
    cursor,
  });
  await assert.rejects(service.listRtTaskHistory({
    operatorUid: AUTH.operatorUid, signInProvider: 'anonymous',
  }, {}), { code: 'permission-denied' });

  for (const input of [
    { pageSize: 0 },
    { pageSize: 51 },
    { pageSize: 1.5 },
    { pageSize: '25' },
    { pageSize: null },
    { cursor: null },
    { cursor: 'not base64!' },
    { cursor: Buffer.from('{}').toString('base64url') },
    { cursor: 'a'.repeat(257) },
    { rtId: 'rt-other' },
    { actorUid: AUTH.operatorUid },
    { operatorUid: AUTH.operatorUid },
  ]) {
    await assert.rejects(service.listRtTaskHistory(AUTH, input), { code: 'invalid-argument' });
  }
  await assert.rejects(service.listRtTaskHistory(AUTH, null), { code: 'invalid-argument' });
});

test('cancellation accepts only task and command IDs and stores the command hash only', async () => {
  const { repository, service } = setup();
  const taskId = 'b'.repeat(40);
  const result = await service.cancelTaskCampaign(AUTH, { taskId, commandId: COMMAND_ID });
  assert.deepEqual(result, { taskId, status: 'CANCELLED' });
  assert.deepEqual(repository.cancellations[0], {
    operatorUid: AUTH.operatorUid,
    taskId,
    commandHash: crypto.createHash('sha256').update(COMMAND_ID).digest('hex'),
    now: NOW,
  });
  assert.equal('commandId' in repository.cancellations[0], false);
  await assert.rejects(service.cancelTaskCampaign(AUTH, {
    taskId,
    commandId: COMMAND_ID,
    rtId: 'rt-a',
  }), { code: 'invalid-argument' });
  await assert.rejects(service.cancelTaskCampaign(AUTH, {
    taskId,
    commandId: COMMAND_ID,
    actorUid: AUTH.operatorUid,
  }), { code: 'invalid-argument' });
  await assert.rejects(service.cancelTaskCampaign({
    operatorUid: AUTH.operatorUid, signInProvider: 'anonymous',
  }, { taskId, commandId: COMMAND_ID }), { code: 'permission-denied' });
});

test('closure accepts only task and command IDs and stores a hash', async () => {
  const { repository, service } = setup();
  const taskId = 'd'.repeat(40);
  const result = await service.closeTaskCampaign(AUTH, { taskId, commandId: COMMAND_ID });
  assert.deepEqual(result, { taskId, status: 'CLOSED' });
  assert.deepEqual(repository.closures[0], {
    operatorUid: AUTH.operatorUid,
    taskId,
    commandHash: crypto.createHash('sha256').update(COMMAND_ID).digest('hex'),
    now: NOW,
  });
  assert.equal('commandId' in repository.closures[0], false);
  await assert.rejects(service.closeTaskCampaign(AUTH, {
    taskId,
    commandId: COMMAND_ID,
    rtId: 'rt-a',
  }), { code: 'invalid-argument' });
  await assert.rejects(service.closeTaskCampaign({
    operatorUid: AUTH.operatorUid, signInProvider: 'anonymous',
  }, { taskId, commandId: COMMAND_ID }), { code: 'permission-denied' });
});

test('lifecycle history returns only bounded public event types and times', async () => {
  const { repository, service } = setup();
  const taskId = 'e'.repeat(40);
  repository.lifecycleEvents = [
    { eventType: 'ACTIVATED', occurredAt: NOW, actorUid: 'private-actor' },
    { eventType: 'CLOSED', occurredAt: new Date(NOW.getTime() + 1000), actorUid: 'private-actor' },
  ];
  const result = await service.listTaskLifecycleEvents(AUTH, { taskId });
  assert.deepEqual(Object.keys(result), ['events']);
  assert.deepEqual(result.events, [
    { eventType: 'ACTIVATED', occurredAt: NOW.toISOString() },
    { eventType: 'CLOSED', occurredAt: new Date(NOW.getTime() + 1000).toISOString() },
  ]);
  assert.deepEqual(Object.keys(result.events[0]).sort(), ['eventType', 'occurredAt']);
  assert.deepEqual(repository.lifecycleRequests[0], {
    operatorUid: AUTH.operatorUid,
    taskId,
  });
  await assert.rejects(service.listTaskLifecycleEvents(AUTH, { taskId, rtId: 'rt-b' }), {
    code: 'invalid-argument',
  });
  await assert.rejects(service.listTaskLifecycleEvents({
    operatorUid: AUTH.operatorUid, signInProvider: 'anonymous',
  }, { taskId }), { code: 'permission-denied' });
  repository.lifecycleEvents = [
    { eventType: 'ACTIVATED', occurredAt: NOW },
    { eventType: 'ACTIVATED', occurredAt: new Date(NOW.getTime() + 1000) },
  ];
  await assert.rejects(service.listTaskLifecycleEvents(AUTH, { taskId }), {
    code: 'failed-precondition',
  });
});
