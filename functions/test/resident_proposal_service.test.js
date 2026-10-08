const test = require('node:test');
const assert = require('node:assert/strict');
const {
  ResidentProposalService,
  proposalDocumentId,
} = require('../src/resident_proposal_service');

const NOW = new Date('2026-10-04T12:00:00.000Z');
const SESSION_TOKEN = 's'.repeat(43);
const REQUEST_ID = 'r'.repeat(43);
const AUTH = { operatorUid: 'operator-a', signInProvider: 'password' };

class FakeSessions {
  async validateSession(token) {
    if (token !== SESSION_TOKEN) {
      const error = new Error('invalid session');
      error.code = 'permission-denied';
      throw error;
    }
    return {
      residentId: 'resident-a',
      communityId: 'rt-a',
      nickname: 'Rani',
    };
  }
}

class FakeRepository {
  constructor() {
    this.proposals = new Map();
    this.campaigns = new Map();
    this.operatorRtIds = new Map([['operator-a', 'rt-a'], ['operator-b', 'rt-b']]);
  }

  async submitProposal(input) {
    assert.equal(input.residentId, 'resident-a');
    assert.equal(input.rtId, 'rt-a');
    const existing = this.proposals.get(input.proposalId);
    if (existing) {
      if (existing.requestFingerprint !== input.requestFingerprint) {
        const error = new Error('request id conflict');
        error.code = 'already-exists';
        throw error;
      }
      return structuredClone(existing);
    }
    const record = {
      proposalId: input.proposalId,
      rtId: input.rtId,
      residentId: input.residentId,
      title: input.title,
      description: input.description,
      category: input.category,
      locationReference: input.locationReference,
      state: 'SUBMITTED',
      submittedAt: input.now,
      requestFingerprint: input.requestFingerprint,
    };
    this.proposals.set(input.proposalId, record);
    return structuredClone(record);
  }

  async listProposals({ operatorUid }) {
    const rtId = this.operatorRtIds.get(operatorUid);
    if (!rtId) {
      const error = new Error('operator access denied');
      error.code = 'permission-denied';
      throw error;
    }
    return {
      items: [...this.proposals.values()]
        .filter((item) => item.rtId === rtId && item.state === 'SUBMITTED')
        .map((item) => ({ ...structuredClone(item), nickname: 'Rani' })),
      isPartial: false,
    };
  }

  async reviewProposal(input) {
    const record = this.proposals.get(input.proposalId);
    if (!record || record.rtId !== this.operatorRtIds.get(input.operatorUid)) {
      const error = new Error('operator access denied');
      error.code = 'permission-denied';
      throw error;
    }
    if (['DISMISSED', 'NEEDS_OFFICIAL_REPORT'].includes(record.state)) {
      if (record.reviewDecision === input.decision &&
          record.reviewCommandHash === input.commandHash &&
          record.reviewedByOperatorUid === input.operatorUid) return structuredClone(record);
      const error = new Error('already reviewed');
      error.code = 'failed-precondition';
      throw error;
    }
    Object.assign(record, {
      state: input.decision,
      reviewDecision: input.decision,
      reviewCommandHash: input.commandHash,
      reviewedByOperatorUid: input.operatorUid,
      reviewedAt: input.now,
    });
    return structuredClone(record);
  }
}

function setup() {
  const repository = new FakeRepository();
  const service = new ResidentProposalService(repository, new FakeSessions(), {
    clock: () => new Date(NOW),
  });
  return { repository, service };
}

function payload(overrides = {}) {
  return {
    sessionToken: SESSION_TOKEN,
    requestId: REQUEST_ID,
    title: 'Lapor tumpukan sampah',
    description: 'Ada sampah di area umum dan jalan utama setelah hujan.',
    category: 'ENVIRONMENTAL_CLEANUP',
    locationReference: 'COMMUNITY_GENERAL_AREA',
    ...overrides,
  };
}

test('submits a deterministic, idempotent SUBMITTED proposal using server session identity', async () => {
  const { repository, service } = setup();
  const first = await service.submitResidentProposal(payload());
  const replay = await service.submitResidentProposal(payload());

  assert.deepEqual(replay, first);
  assert.equal(repository.proposals.size, 1);
  assert.equal(first.proposalId, proposalDocumentId('rt-a', 'resident-a', REQUEST_ID));
  assert.equal(first.state, 'SUBMITTED');
  assert.equal(first.submittedAt, NOW.toISOString());
  assert.equal(repository.proposals.get(first.proposalId).residentId, 'resident-a');
  assert.equal(repository.proposals.get(first.proposalId).rtId, 'rt-a');
  assert.equal('residentId' in first, false);
  assert.equal('rtId' in first, false);
  assert.equal(repository.campaigns.size, 0);
});

test('proposal content that describes a hazardous task remains a proposal, never an active task', async () => {
  const { repository, service } = setup();
  const result = await service.submitResidentProposal(payload({
    title: 'Bersihkan saluran drainase',
    description: 'Usul agar warga masuk ke drainase dan mengangkat sampah dari dalam saluran.',
  }));
  assert.equal(result.state, 'SUBMITTED');
  assert.equal(repository.proposals.get(result.proposalId).description,
    'Usul agar warga masuk ke drainase dan mengangkat sampah dari dalam saluran.');
  assert.equal(repository.campaigns.size, 0);
  assert.equal([...repository.proposals.values()].some((item) => item.state === 'ACTIVE'), false);
});

test('same request id with changed content is not treated as a successful replay', async () => {
  const { service } = setup();
  await service.submitResidentProposal(payload());
  await assert.rejects(
    service.submitResidentProposal(payload({ description: 'Isi permintaan berbeda.' })),
    { code: 'already-exists' },
  );
});

test('rejects forged identity, unknown fields, invalid category and location references', async () => {
  const { service } = setup();
  for (const forged of [
    { ...payload(), residentId: 'attacker' },
    { ...payload(), rtId: 'rt-b' },
    { ...payload(), operatorUid: 'operator-a' },
    { ...payload(), category: 'EMERGENCY_RESPONSE' },
    { ...payload(), locationReference: 'Jalan Merdeka' },
    { ...payload(), locationReference: 'GPS_COORDINATE' },
    { ...payload(), requestId: 'too-short' },
  ]) {
    await assert.rejects(service.submitResidentProposal(forged), { code: 'invalid-argument' });
  }
  await assert.rejects(
    service.submitResidentProposal(payload({ sessionToken: 'forged-session' })),
    { code: 'permission-denied' },
  );
});

test('rejects coordinate, NIK, mobile, and address data from title or description', async () => {
  const { service } = setup();
  const forbiddenValues = [
    '-6.200123, 106.816456',
    '-6.2, 106.8',
    'GPS: -6.2',
    'NIK 3175010101900001',
    'NIK 3175 0101 0190 0001',
    'NIK 1234/5678/9012/3456',
    'NIK (1234)/(5678)/(9012)/(3456)',
    'Hubungi 0812-3456-7890',
    'Hubungi 0812/3456/7890',
    'Hubungi (0812) 3456 (7890)',
    'Hubungi +62 812 3456 7890',
    'Alamat Jalan Mawar No. 12',
  ];
  for (const description of forbiddenValues) {
    await assert.rejects(
      service.submitResidentProposal(payload({ description })),
      { code: 'invalid-argument' },
      description,
    );
  }
});

test('enforces bounded text and only exposes pending same-RT operator queue', async () => {
  const { service } = setup();
  const submitted = await service.submitResidentProposal(payload());
  assert.deepEqual(await service.listResidentProposals(AUTH, {}), {
    items: [{
      proposalId: submitted.proposalId,
      title: 'Lapor tumpukan sampah',
      description: 'Ada sampah di area umum dan jalan utama setelah hujan.',
      category: 'ENVIRONMENTAL_CLEANUP',
      locationReference: 'COMMUNITY_GENERAL_AREA',
      state: 'SUBMITTED',
      submittedAt: NOW.toISOString(),
      nickname: 'Rani',
    }],
    isPartial: false,
  });
  assert.deepEqual(await service.listResidentProposals({
    operatorUid: 'operator-b', signInProvider: 'password',
  }, {}), { items: [], isPartial: false });
  await assert.rejects(service.listResidentProposals(AUTH, { rtId: 'rt-b' }), {
    code: 'invalid-argument',
  });
  await assert.rejects(service.submitResidentProposal(payload({ title: 'x'.repeat(101) })), {
    code: 'invalid-argument',
  });
  await assert.rejects(service.submitResidentProposal(payload({ description: 'x'.repeat(1001) })), {
    code: 'invalid-argument',
  });
});

test('review allows only DISMISSED or NEEDS_OFFICIAL_REPORT and is idempotent for the same command', async () => {
  const { service } = setup();
  const submitted = await service.submitResidentProposal(payload());
  await assert.rejects(service.reviewResidentProposal(AUTH, {
    proposalId: submitted.proposalId,
    decision: 'APPROVED',
    commandId: REQUEST_ID,
  }), { code: 'invalid-argument' });
  const review = await service.reviewResidentProposal(AUTH, {
    proposalId: submitted.proposalId,
    decision: 'DISMISSED',
    commandId: REQUEST_ID,
  });
  assert.equal(review.state, 'DISMISSED');
  assert.equal(review.reviewedAt, NOW.toISOString());
  assert.deepEqual(await service.reviewResidentProposal(AUTH, {
    proposalId: submitted.proposalId,
    decision: 'DISMISSED',
    commandId: REQUEST_ID,
  }), review);
  await assert.rejects(service.reviewResidentProposal(AUTH, {
    proposalId: submitted.proposalId,
    decision: 'DISMISSED',
    commandId: 'z'.repeat(43),
  }), { code: 'failed-precondition' });

  // Test NEEDS_OFFICIAL_REPORT
  const submitted2 = await service.submitResidentProposal(payload({ requestId: 'request-for-official-report-0001' }));
  const officialReview = await service.reviewResidentProposal(AUTH, {
    proposalId: submitted2.proposalId,
    decision: 'NEEDS_OFFICIAL_REPORT',
    commandId: REQUEST_ID,
  });
  assert.equal(officialReview.state, 'NEEDS_OFFICIAL_REPORT');
  assert.equal(officialReview.reviewedAt, NOW.toISOString());
  assert.deepEqual(await service.reviewResidentProposal(AUTH, {
    proposalId: submitted2.proposalId,
    decision: 'NEEDS_OFFICIAL_REPORT',
    commandId: REQUEST_ID,
  }), officialReview);
});
