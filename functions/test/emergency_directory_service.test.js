const test = require('node:test');
const assert = require('node:assert/strict');
const { hashSessionToken } = require('../src/resident_session_service');
const {
  EmergencyDirectoryService,
} = require('../src/emergency_directory_service');
const {
  FirestoreEmergencyDirectoryRepository,
} = require('../src/firestore_emergency_directory_repository');

const NOW = new Date('2026-10-04T12:00:00.000Z');
const SESSION_TOKEN = 's'.repeat(43);
const SESSION_HASH = hashSessionToken(SESSION_TOKEN);
const DIRECTORY_FIXTURE = {
  rtId: 'rt-test-only',
  state: 'ACTIVE',
  version: 1,
  lastVerifiedAt: new Date('2026-10-03T12:00:00.000Z'),
  emergencyContacts: [{ label: 'Posko uji', phone: '+62 21 555 0101' }],
  assemblyPoints: [{ label: 'Lapangan uji', publicLocation: 'Balai warga uji' }],
  officialReportChannels: [
    { label: 'Laporan uji', url: 'https://example.gov.id/report' },
    { label: 'Telepon uji', phone: '112' },
  ],
};

class FakeSessions {
  async validateSession(token) {
    if (token !== SESSION_TOKEN) {
      const error = new Error('session denied');
      error.code = 'permission-denied';
      throw error;
    }
    return { residentId: 'resident-test', communityId: 'rt-test-only' };
  }
}

class FakeRepository {
  constructor(directory = DIRECTORY_FIXTURE) {
    this.directory = directory == null ? null : structuredClone(directory);
    this.lastInput = null;
    this.error = null;
  }

  async getDirectoryForResident(input) {
    this.lastInput = input;
    if (this.error) throw this.error;
    return this.directory == null ? null : structuredClone(this.directory);
  }
}

function setup(directory = DIRECTORY_FIXTURE) {
  const repository = new FakeRepository(directory);
  const service = new EmergencyDirectoryService(repository, new FakeSessions(), {
    clock: () => new Date(NOW),
  });
  return { repository, service };
}

function payload(overrides = {}) {
  return { sessionToken: SESSION_TOKEN, ...overrides };
}

test('returns the validated directory for identity derived from the resident session only', async () => {
  const { repository, service } = setup();
  const result = await service.getEmergencyDirectory(payload());
  assert.deepEqual(result, {
    state: 'ACTIVE',
    version: 1,
    lastVerifiedAt: '2026-10-03T12:00:00.000Z',
    emergencyContacts: [{ label: 'Posko uji', phone: '+62 21 555 0101' }],
    assemblyPoints: [{ label: 'Lapangan uji', publicLocation: 'Balai warga uji' }],
    officialReportChannels: [
      { label: 'Laporan uji', url: 'https://example.gov.id/report' },
      { label: 'Telepon uji', phone: '112' },
    ],
  });
  assert.equal(repository.lastInput.sessionIdHash, SESSION_HASH);
  assert.equal(repository.lastInput.residentId, 'resident-test');
  assert.equal(repository.lastInput.rtId, 'rt-test-only');
  assert.equal('residentId' in result, false);
  assert.equal('rtId' in result, false);
});

test('returns explicit unconfigured and disabled states without replacing them with empty contacts', async () => {
  const { service: missingService } = setup(null);
  assert.deepEqual(await missingService.getEmergencyDirectory(payload()), {
    state: 'UNCONFIGURED',
  });

  const disabled = {
    ...structuredClone(DIRECTORY_FIXTURE),
    state: 'DISABLED',
    emergencyContacts: [],
    assemblyPoints: [],
    officialReportChannels: [],
  };
  const { service: disabledService } = setup(disabled);
  assert.deepEqual(await disabledService.getEmergencyDirectory(payload()), {
    state: 'DISABLED',
    version: 1,
    lastVerifiedAt: '2026-10-03T12:00:00.000Z',
  });
});

test('rejects caller-supplied identity and unknown fields', async () => {
  const { service } = setup();
  for (const forged of [
    { residentId: 'resident-other' },
    { rtId: 'rt-other' },
    { operatorUid: 'operator-test' },
    { sessionToken: SESSION_TOKEN, residentId: 'resident-other' },
    { sessionToken: SESSION_TOKEN, rtId: 'rt-other' },
  ]) {
    await assert.rejects(service.getEmergencyDirectory(forged), { code: 'invalid-argument' });
  }
  await assert.rejects(service.getEmergencyDirectory({}), { code: 'permission-denied' });
  await assert.rejects(service.getEmergencyDirectory({ sessionToken: 'forged-token' }), {
    code: 'permission-denied',
  });
});

test('accepts positive integer data revisions for active and disabled directories', async () => {
  const { service: activeService } = setup({
    ...structuredClone(DIRECTORY_FIXTURE),
    version: 42,
  });
  assert.equal((await activeService.getEmergencyDirectory(payload())).version, 42);

  const { service: disabledService } = setup({
    ...structuredClone(DIRECTORY_FIXTURE),
    state: 'DISABLED',
    version: 43,
    emergencyContacts: [],
    assemblyPoints: [],
    officialReportChannels: [],
  });
  assert.equal((await disabledService.getEmergencyDirectory(payload())).version, 43);
});

test('rejects malformed, unsupported, or cross-RT stored directory schemas', async () => {
  const invalidRecords = [
    { ...structuredClone(DIRECTORY_FIXTURE), version: 0 },
    { ...structuredClone(DIRECTORY_FIXTURE), version: 1.5 },
    { ...structuredClone(DIRECTORY_FIXTURE), version: Number.MAX_SAFE_INTEGER + 1 },
    { ...structuredClone(DIRECTORY_FIXTURE), state: 'PENDING' },
    { ...structuredClone(DIRECTORY_FIXTURE), rtId: 'rt-other' },
    { ...structuredClone(DIRECTORY_FIXTURE), extra: 'not in schema' },
    { ...structuredClone(DIRECTORY_FIXTURE), emergencyContacts: [{ label: 'Posko', phone: 'not-phone' }] },
    { ...structuredClone(DIRECTORY_FIXTURE), assemblyPoints: [{ label: 'Titik', publicLocation: '' }] },
    { ...structuredClone(DIRECTORY_FIXTURE), officialReportChannels: [{ label: 'Laporan', url: 'http://example.gov.id' }] },
    { ...structuredClone(DIRECTORY_FIXTURE), officialReportChannels: [{ label: 'Laporan' }] },
    { ...structuredClone(DIRECTORY_FIXTURE), officialReportChannels: [{ label: 'Laporan', url: 'http://example.gov.id', phone: '112' }] },
    { ...structuredClone(DIRECTORY_FIXTURE), emergencyContacts: [] },
    { ...structuredClone(DIRECTORY_FIXTURE), lastVerifiedAt: new Date('2026-10-05T12:00:00.000Z') },
  ];
  for (const record of invalidRecords) {
    const { service } = setup(record);
    await assert.rejects(service.getEmergencyDirectory(payload()), {
      code: 'failed-precondition',
      message: 'Direktori darurat tidak valid.',
    });
  }
});

test('does not convert an unavailable repository into unconfigured and erase a valid cache', async () => {
  const { repository, service } = setup(null);
  const unavailable = new Error('backend storage unavailable');
  unavailable.code = 'unavailable';
  repository.error = unavailable;
  await assert.rejects(service.getEmergencyDirectory(payload()), (error) => error === unavailable);
});

class FakeSnapshot {
  constructor(id, value) {
    this.id = id;
    this.value = value;
    this.exists = value !== undefined;
  }
  data() { return this.value; }
}

class FakeFirestore {
  constructor(documents) {
    this.documents = documents;
    this.pathsRead = [];
  }
  collection(name) {
    return { doc: (id) => ({ path: `${name}/${id}`, id }) };
  }
  async runTransaction(callback) {
    return callback({
      get: async (ref) => {
        this.pathsRead.push(ref.path);
        return new FakeSnapshot(ref.id, this.documents.get(ref.path));
      },
    });
  }
}

function transactionFixture(overrides = {}) {
  const documents = new Map([
    [`resident_sessions/${SESSION_HASH}`, {
      active: true, residentId: 'resident-test', rtId: 'rt-test-only',
      expiresAt: new Date('2026-10-11T12:00:00.000Z'),
    }],
    ['resident_profiles/resident-test', { rtId: 'rt-test-only', nickname: 'Warga uji' }],
    ['rt_communities/rt-test-only', { displayName: 'RT uji' }],
    ['emergency_directories/rt-test-only', structuredClone(DIRECTORY_FIXTURE)],
  ]);
  for (const [path, value] of Object.entries(overrides)) documents.set(path, value);
  return documents;
}

test('repository rechecks session, resident profile, and RT in one transaction and reads only the scoped directory', async () => {
  const firestore = new FakeFirestore(transactionFixture());
  const repository = new FirestoreEmergencyDirectoryRepository(firestore);
  const result = await repository.getDirectoryForResident({
    sessionIdHash: SESSION_HASH,
    residentId: 'resident-test',
    rtId: 'rt-test-only',
    now: NOW,
  });
  assert.deepEqual(result, DIRECTORY_FIXTURE);
  assert.deepEqual(firestore.pathsRead.sort(), [
    `resident_sessions/${SESSION_HASH}`,
    'resident_profiles/resident-test',
    'rt_communities/rt-test-only',
    'emergency_directories/rt-test-only',
  ].sort());

  for (const overrides of [
    { [`resident_sessions/${SESSION_HASH}`]: { active: false } },
    { 'resident_profiles/resident-test': { rtId: 'rt-other', nickname: 'Warga uji' } },
    { 'rt_communities/rt-test-only': undefined },
  ]) {
    const invalidFirestore = new FakeFirestore(transactionFixture(overrides));
    const invalidRepository = new FirestoreEmergencyDirectoryRepository(invalidFirestore);
    await assert.rejects(invalidRepository.getDirectoryForResident({
      sessionIdHash: SESSION_HASH,
      residentId: 'resident-test',
      rtId: 'rt-test-only',
      now: NOW,
    }), { code: 'permission-denied' });
  }
});
