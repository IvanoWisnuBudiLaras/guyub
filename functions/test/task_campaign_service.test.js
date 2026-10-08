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
    this.activeCampaigns = [];
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
