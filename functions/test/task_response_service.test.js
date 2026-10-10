const test = require('node:test');
const assert = require('node:assert/strict');
const {
  TaskResponseService,
  normalizeCompletionNote,
  responseDocumentId,
} = require('../src/task_response_service');
const { hashSessionToken } = require('../src/resident_session_service');

const SESSION_TOKEN = 'resident-session-token-0123456789';
const COMMAND_ID = 'c'.repeat(40);
const TASK_ID = 'a'.repeat(40);
const RESPONSE_ID = responseDocumentId('rt-a', TASK_ID, 'resident-a');
const OPERATOR = { operatorUid: 'operator-a', signInProvider: 'password' };
const SNAPSHOT = {
  templateId: 'household_ready',
  version: 1,
  title: 'Siapkan perlengkapan keluarga',
  category: 'HOUSEHOLD_PREPARATION',
  coreInstruction: 'Simpan dokumen penting di tempat yang mudah dijangkau.',
  safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik basah.',
};

class FakeRepository {
  constructor() {
    this.calls = [];
  }
  async listActiveTasks(input) {
    this.calls.push(['listActiveTasks', input]);
    return { items: [{
      campaign: {
        campaignId: TASK_ID,
        rtId: 'rt-a',
        templateSnapshot: SNAPSHOT,
        deadline: new Date('2026-10-05T12:00:00.000Z'),
        locationReference: 'COMMUNITY_GENERAL_AREA',
        additionalNote: 'Masuk ke saluran air untuk membersihkan sampah',
        status: 'ACTIVE',
      },
      response: null,
    }], isPartial: false };
  }
  async recordParticipation(input) {
    this.calls.push(['recordParticipation', input]);
    return {
      taskId: input.taskId,
      participationState: input.choice,
      completionState: 'NOT_SUBMITTED',
    };
  }
  async submitCompletion(input) {
    this.calls.push(['submitCompletion', input]);
    return {
      taskId: input.taskId,
      participationState: 'JOINED',
      completionState: 'PENDING_RT_VERIFICATION',
      completionNote: input.completionNote,
      completionSubmittedAt: input.now,
      evidenceId: input.evidenceId ?? null,
    };
  }
  async listPendingVerifications(input) {
    this.calls.push(['listPendingVerifications', input]);
    return { items: [{
      responseId: RESPONSE_ID,
      taskId: TASK_ID,
      taskTitle: SNAPSHOT.title,
      nickname: 'Warga A',
      completionNote: null,
      completionSubmittedAt: new Date('2026-10-04T12:00:00.000Z'),
    }], isPartial: false };
  }
  async verifyCompletion(input) {
    this.calls.push(['verifyCompletion', input]);
    return {
      taskId: TASK_ID,
      participationState: 'JOINED',
      completionState: 'VERIFIED_COMPLETE',
      verifiedAt: input.now,
    };
  }
  async getResponseRecap(input) {
    this.calls.push(['getResponseRecap', input]);
    return {
      taskId: input.taskId,
      rtId: 'rt-a',
      taskTitle: SNAPSHOT.title,
      recordedResponseCount: 2,
      joinedCount: 1,
      declinedCount: 1,
      pendingVerificationCount: 0,
      verifiedCompleteCount: 1,
      isPartial: false,
    };
  }
}

function createService(repository = new FakeRepository()) {
  const residentSessionService = {
    async validateSession(token) {
      assert.equal(token, SESSION_TOKEN);
      return { residentId: 'resident-a', communityId: 'rt-a', nickname: 'Warga A' };
    },
  };
  return {
    repository,
    service: new TaskResponseService(repository, residentSessionService, {
      clock: () => new Date('2026-10-04T12:00:00.000Z'),
    }),
  };
}

test('resident task listing derives the RT from the validated session and returns only safe task fields', async () => {
  const { repository, service } = createService();
  const result = await service.listResidentActiveTasks({ sessionToken: SESSION_TOKEN });
  assert.deepEqual(repository.calls[0][1], {
    sessionIdHash: hashSessionToken(SESSION_TOKEN),
    residentId: 'resident-a',
    rtId: 'rt-a',
    now: new Date('2026-10-04T12:00:00.000Z'),
  });
  assert.equal(result.items[0].taskId, TASK_ID);
  assert.equal(result.items[0].rtId, 'rt-a');
  assert.equal(result.items[0].participationState, 'UNRESPONDED');
  assert.equal(result.items[0].completionState, 'NOT_SUBMITTED');
  assert.equal(result.isPartial, false);
  assert.equal(result.items[0].templateSnapshot.safetyInstruction, SNAPSHOT.safetyInstruction);
  assert.equal(JSON.stringify(result).includes(SESSION_TOKEN), false);
  assert.equal('residentId' in result.items[0], false);
  assert.equal('additionalNote' in result.items[0], false);
});

test('resident requests reject caller-supplied identity and unknown fields', async () => {
  const { service } = createService();
  await assert.rejects(
    service.listResidentActiveTasks({ sessionToken: SESSION_TOKEN, rtId: 'rt-b' }),
    { code: 'invalid-argument' },
  );
  await assert.rejects(
    service.recordResidentTaskResponse({
      sessionToken: SESSION_TOKEN,
      taskId: TASK_ID,
      choice: 'JOINED',
      commandId: COMMAND_ID,
      residentId: 'resident-b',
    }),
    { code: 'invalid-argument' },
  );
});

test('resident participation accepts only voluntary JOINED or DECLINED choice and hashes command ID', async () => {
  const { repository, service } = createService();
  const result = await service.recordResidentTaskResponse({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    choice: 'DECLINED',
    commandId: COMMAND_ID,
  });
  assert.equal(result.participationState, 'DECLINED');
  const call = repository.calls[0][1];
  assert.equal(call.choice, 'DECLINED');
  assert.notEqual(call.commandHash, COMMAND_ID);
  assert.equal(call.commandHash.length, 64);
  await assert.rejects(service.recordResidentTaskResponse({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    choice: 'PUNISHED',
    commandId: COMMAND_ID,
  }), { code: 'invalid-argument' });
});

test('completion note is optional, bounded, normalized, and excludes common address/GPS content', () => {
  assert.equal(normalizeCompletionNote('  Sudah disiapkan  '), 'Sudah disiapkan');
  assert.equal(normalizeCompletionNote('   '), null);
  assert.equal(normalizeCompletionNote(null), null);
  assert.throws(() => normalizeCompletionNote('Alamat Jalan Merdeka 10'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Lokasi -6.12345, 106.12345'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('-6.2, 106.8'), {
    code: 'invalid-argument',
  });
  for (const coordinate of [
    '-6,2088, 106,8456',
    '-6,2088 106,8456',
    '6.2088 S, 106.8456 E',
    '6,2088 LS, 106,8456 BT',
    'S 6.2088, E 106.8456',
    'LS 6,2088, BT 106,8456',
    '6.2088° S, 106.8456° E',
    'S 6.2088°, E 106.8456°',
    'GPS: -6.2',
    'GPS: -6,2',
    'lat: -6.2088',
    'latitude: 6.2088 S',
    'lon: 106.8456',
    'koordinat: -6.2088, 106.8456',
    'koordinat: -6,2088, 106,8456',
    String.raw`7°45'22"S, 110°22'05"E`,
    String.raw`7° 45′ 22″ S; 110° 22′ 05″ E`,
    String.raw`S 7° 45′ 22″; E 110° 22′ 05″`,
    String.raw`LS 7° 45′ 22″, BT 110° 22′ 05″`,
    String.raw`7 45 22 S, 110 22 05 E`,
    String.raw`S 7 45 22, E 110 22 05`,
    String.raw`S 7° 45.5', E 110° 22.5'`,
    String.raw`N 0° 45′ 22″, W 100° 22′ 05″`,
    String.raw`7°45.366′S 110°22.083′E`,
    String.raw`Koordinat: 7°45′22″, 110°22′05″`,
  ]) {
    assert.throws(() => normalizeCompletionNote(coordinate), {
      code: 'invalid-argument',
    }, coordinate);
  }
  assert.equal(
    normalizeCompletionNote('Curah hujan 7,5 mm; dokumen sudah disiapkan.'),
    'Curah hujan 7,5 mm; dokumen sudah disiapkan.',
  );
  assert.throws(() => normalizeCompletionNote('NIK 1234567890123456'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Hubungi 081234567890'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK 1234 5678 9012 3456'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Hubungi 0812 3456 7890'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Hubungi +62 812-3456-7890'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK 1234/5678/9012/3456'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Hubungi 0812/3456/7890'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK (1234)/(5678)/(9012)/(3456)'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK 3175-0101-0190-0001'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK 3175.0101.0190.0001'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('NIK 3175_0101_0190_0001'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('3175  0101  0190  0001'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('3175,0101,0190,0001'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('Hubungi (0812) 3456 (7890)'), {
    code: 'invalid-argument',
  });
  assert.throws(() => normalizeCompletionNote('x'.repeat(501)), {
    code: 'invalid-argument',
  });
});

test('completion evidence reference is optional, bounded, and server-scoped', async () => {
  const { repository, service } = createService();
  const evidenceId = 'b'.repeat(40);
  const withEvidence = await service.submitTaskCompletion({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    note: null,
    commandId: COMMAND_ID,
    evidenceId,
  });
  assert.equal(withEvidence.evidenceId, evidenceId);
  assert.equal(repository.calls[0][1].evidenceId, evidenceId);
  await assert.rejects(service.submitTaskCompletion({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    note: null,
    commandId: 'c'.repeat(40),
    evidenceId: 'not-an-evidence-id',
  }), { code: 'invalid-argument' });
  await assert.rejects(service.submitTaskCompletion({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    note: null,
    commandId: 'c'.repeat(40),
    evidenceId,
    residentId: 'forged-resident',
  }), { code: 'invalid-argument' });
});

test('completion submission and verification accept only a password-authenticated operator', async () => {
  const { repository, service } = createService();
  const completion = await service.submitTaskCompletion({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    note: 'Sudah disiapkan',
    commandId: COMMAND_ID,
  });
  assert.equal(completion.completionState, 'PENDING_RT_VERIFICATION');
  assert.equal(repository.calls[0][1].completionNote, 'Sudah disiapkan');
  assert.equal(repository.calls[0][1].commandHash.length, 64);

  await assert.rejects(service.listPendingTaskVerifications(
    { operatorUid: 'operator-a', signInProvider: 'anonymous' },
    {},
  ), { code: 'permission-denied' });
  const pending = await service.listPendingTaskVerifications(OPERATOR, {});
  assert.equal(pending.items[0].nickname, 'Warga A');
  assert.equal(pending.isPartial, false);
  assert.equal('residentId' in pending.items[0], false);

  const verified = await service.verifyTaskCompletion(OPERATOR, {
    responseId: RESPONSE_ID,
    commandId: COMMAND_ID,
  });
  assert.equal(verified.completionState, 'VERIFIED_COMPLETE');
  assert.equal(repository.calls.at(-1)[1].responseId, RESPONSE_ID);
  assert.notEqual(repository.calls.at(-1)[1].commandHash, COMMAND_ID);
});

test('recap is response-only aggregate data without a non-response count or resident list', async () => {
  const { service } = createService();
  const recap = await service.getTaskResponseRecap(OPERATOR, { taskId: TASK_ID });
  assert.deepEqual(recap, {
    taskId: TASK_ID,
    rtId: 'rt-a',
    taskTitle: SNAPSHOT.title,
    recordedResponseCount: 2,
    joinedCount: 1,
    declinedCount: 1,
    pendingVerificationCount: 0,
    verifiedCompleteCount: 1,
    isPartial: false,
  });
  assert.equal('nonResponseCount' in recap, false);
  assert.equal('residentId' in recap, false);
});
