const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ProxyResidentService,
  proxyResidentDocumentId,
  normalizeProxyNickname,
  normalizeHouseNumber,
} = require('../src/proxy_resident_service');

const NOW = new Date('2026-10-06T12:00:00.000Z');
const AUTH = { operatorUid: 'operator-a', signInProvider: 'password' };
const REQUEST_ID = 'r'.repeat(43);
const COMMAND_ID = 'c'.repeat(43);
const RESIDENT_ID = 'a'.repeat(40);
const TASK_ID = 'b'.repeat(40);

class FakeRepository {
  constructor() { this.calls = []; }
  async getOperatorRtId(operatorUid) {
    assert.equal(operatorUid, 'operator-a');
    return 'rt-a';
  }
  async createProxyResident(input) {
    this.calls.push(['createProxyResident', input]);
    return {
      residentId: input.residentId,
      nickname: input.nickname,
      houseNumber: input.houseNumber,
      needsAssistance: input.needsAssistance,
      createdAt: input.now,
    };
  }
  async cancelProxyResidentCreate(input) {
    this.calls.push(['cancelProxyResidentCreate', input]);
    return { state: 'CANCELLED' };
  }
  async listProxyResidents(input) {
    this.calls.push(['listProxyResidents', input]);
    return { items: [], isPartial: false };
  }
  async getProxyTaskStatus(input) {
    this.calls.push(['getProxyTaskStatus', input]);
    return {
      taskId: input.taskId,
      participationState: 'UNRESPONDED',
      completionState: 'NOT_SUBMITTED',
    };
  }
  async updateProxyAssistance(input) {
    this.calls.push(['updateProxyAssistance', input]);
    return { residentId: input.residentId, needsAssistance: input.needsAssistance };
  }
  async updateProxyTaskStatus(input) {
    this.calls.push(['updateProxyTaskStatus', input]);
    return {
      taskId: input.taskId,
      participationState: input.participationState,
      completionState: input.completionReported ? 'PENDING_RT_VERIFICATION' : 'NOT_SUBMITTED',
    };
  }
}

function setup(repository = new FakeRepository()) {
  const service = new ProxyResidentService(repository, { clock: () => new Date(NOW) });
  return { service, repository };
}

test('proxy profile stores only a nickname, optional house number and assistance marker', async () => {
  const { service, repository } = setup();
  const input = {
    nickname: '  Bu Sari  ', houseNumber: '12A', needsAssistance: true,
    residentConsentConfirmed: true, requestId: REQUEST_ID,
  };
  const created = await service.createProxyResident(AUTH, input);
  assert.deepEqual(created, {
    residentId: proxyResidentDocumentId('rt-a', REQUEST_ID),
    nickname: 'Bu Sari', houseNumber: '12A', needsAssistance: true,
    deletionPending: false,
    createdAt: NOW.toISOString(),
  });
  const call = repository.calls[0][1];
  assert.equal(call.expectedRtId, 'rt-a');
  assert.equal('createdBy' in call, false);
  assert.equal(call.residentConsentConfirmed, true);
  assert.equal(call.requestHash.length, 64);
  assert.equal('rtId' in created, false);
  assert.equal(JSON.stringify(created).includes('operator-a'), false);
});

test('canceling an uncertain create is scoped and server-confirmed', async () => {
  const { service, repository } = setup();
  const result = await service.cancelPendingProxyResidentCreate(AUTH, { requestId: REQUEST_ID });
  assert.deepEqual(result, { state: 'CANCELLED' });
  const call = repository.calls[0];
  assert.equal(call[0], 'cancelProxyResidentCreate');
  assert.equal(call[1].expectedRtId, 'rt-a');
  assert.equal(call[1].residentId, proxyResidentDocumentId('rt-a', REQUEST_ID));
  assert.equal(call[1].requestHash.length, 64);
});

test('proxy profile input is bounded and rejects forbidden personal data and caller identity', async () => {
  const { service } = setup();
  for (const nickname of ['Alamat Jalan Mawar No 12', 'NIK 1234567890123456', '081234567890', '-6.2,106.8']) {
    await assert.rejects(service.createProxyResident(AUTH, {
      nickname, residentConsentConfirmed: true, requestId: REQUEST_ID,
    }), { code: 'invalid-argument' });
  }
  for (const houseNumber of ['Jalan Mawar 12', '12/5', '-6.2', '081234567890']) {
    await assert.rejects(service.createProxyResident(AUTH, {
      nickname: 'Warga A', houseNumber, residentConsentConfirmed: true, requestId: REQUEST_ID,
    }), { code: 'invalid-argument' });
  }
  await assert.rejects(service.createProxyResident(AUTH, {
    nickname: 'Warga A', residentConsentConfirmed: false, requestId: REQUEST_ID,
  }), { code: 'failed-precondition' });
  await assert.rejects(service.createProxyResident(AUTH, {
    nickname: 'Warga A', residentConsentConfirmed: true, requestId: REQUEST_ID, rtId: 'rt-b',
  }), { code: 'invalid-argument' });
  assert.equal(normalizeProxyNickname('  Nenek  '), 'Nenek');
  assert.equal(normalizeHouseNumber(null), null);
});

test('proxy operations require password-authenticated operator and explicit consent attestation', async () => {
  const { service } = setup();
  await assert.rejects(service.createProxyResident({
    operatorUid: 'operator-a', signInProvider: 'anonymous',
  }, { nickname: 'Warga', residentConsentConfirmed: true, requestId: REQUEST_ID }), {
    code: 'permission-denied',
  });
  await assert.rejects(service.updateProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID, participationState: 'JOINED',
    completionReported: false, residentConsentConfirmed: false, commandId: COMMAND_ID,
  }), { code: 'failed-precondition' });
});

test('proxy status is constrained to voluntary choice and optional completion remains pending RT verification', async () => {
  const { service, repository } = setup();
  const result = await service.updateProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID, participationState: 'JOINED',
    completionReported: true, residentConsentConfirmed: true, commandId: COMMAND_ID,
  });
  assert.deepEqual(result, {
    taskId: TASK_ID, participationState: 'JOINED',
    completionState: 'PENDING_RT_VERIFICATION',
  });
  const call = repository.calls[0][1];
  assert.equal(call.operatorUid, 'operator-a');
  assert.equal(call.rtId, 'rt-a');
  assert.equal(call.commandHash.length, 64);
  assert.notEqual(call.commandHash, COMMAND_ID);
  await assert.rejects(service.updateProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID, participationState: 'PUNISHED',
    completionReported: false, residentConsentConfirmed: true, commandId: COMMAND_ID,
  }), { code: 'invalid-argument' });
  await assert.rejects(service.updateProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID, participationState: 'DECLINED',
    completionReported: true, residentConsentConfirmed: true, commandId: COMMAND_ID,
  }), { code: 'invalid-argument' });
  assert.equal('residentId' in result, false);
});

test('proxy task status reads are operator scoped and neutral before a response', async () => {
  const { service, repository } = setup();
  const result = await service.getProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID,
  });
  assert.deepEqual(result, {
    taskId: TASK_ID,
    participationState: 'UNRESPONDED',
    completionState: 'NOT_SUBMITTED',
  });
  assert.deepEqual(repository.calls[0], ['getProxyTaskStatus', {
    operatorUid: 'operator-a', rtId: 'rt-a', residentId: RESIDENT_ID, taskId: TASK_ID,
  }]);
  await assert.rejects(service.getProxyTaskStatus(AUTH, {
    residentId: RESIDENT_ID, taskId: TASK_ID, rtId: 'rt-b',
  }), { code: 'invalid-argument' });
});

test('proxy assistance updates and lists do not allow caller-supplied RT scope', async () => {
  const { service, repository } = setup();
  await service.listProxyResidents(AUTH, {});
  await service.updateProxyAssistance(AUTH, {
    residentId: RESIDENT_ID, needsAssistance: true,
    residentConsentConfirmed: true, commandId: COMMAND_ID,
  });
  assert.equal(repository.calls[0][1].operatorUid, 'operator-a');
  assert.equal(repository.calls[1][1].residentConsentConfirmed, true);
  await assert.rejects(service.listProxyResidents(AUTH, { rtId: 'rt-b' }), {
    code: 'invalid-argument',
  });
});
