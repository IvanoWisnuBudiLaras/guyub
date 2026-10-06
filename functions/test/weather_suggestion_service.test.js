const test = require('node:test');
const assert = require('node:assert/strict');
const {
  WeatherSuggestionService,
  normalizeBmkgSnapshot,
} = require('../src/weather_suggestion_service');

const NOW = new Date('2026-10-05T12:00:00.000Z');
const SOURCE_UPDATED_AT = new Date('2026-10-05T06:00:00.000Z');
const AUTH = { operatorUid: 'operator-a', signInProvider: 'password' };

function source(overrides = {}) {
  return {
    sourceId: 'rt-a',
    rtId: 'rt-a',
    source: 'BMKG',
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'weather-reviewer',
    reviewedAt: new Date('2026-10-01T00:00:00.000Z'),
    endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1001',
    maximumAgeSeconds: 86400,
    normalization: {
      rainfallMmPath: ['data', 0, 'forecast', 'rainfall_mm'],
      sourceUpdatedAtPath: ['data', 0, 'forecast', 'source_updated_at'],
    },
    ...overrides,
  };
}

function payload({ rainfallMm = 32.5, sourceUpdatedAt = SOURCE_UPDATED_AT.toISOString() } = {}) {
  return {
    data: [{ forecast: { rainfall_mm: rainfallMm, source_updated_at: sourceUpdatedAt } }],
  };
}

function rule(overrides = {}) {
  return {
    ruleId: 'heavy-rain-preparation',
    version: 1,
    rtId: 'rt-a',
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'weather-reviewer',
    reviewedAt: new Date('2026-10-01T00:00:00.000Z'),
    minimumRainfallMm: 25,
    suggestedTemplateVersions: [{ templateId: 'home-check', version: 2, fingerprint: 'a'.repeat(64) }],
    explanation: 'Tinjau persiapan rumah tangga berdasarkan konteks prakiraan BMKG.',
    ...overrides,
  };
}

class FakeRepository {
  constructor({ sources = [source()], rules = [rule()], lastSnapshots = {} } = {}) {
    this.sources = sources;
    this.rules = rules;
    this.lastSnapshots = new Map(Object.entries(lastSnapshots));
    this.snapshots = [];
    this.suggestions = new Map();
    this.operatorLookups = [];
    this.activeCampaigns = [];
  }
  async listEnabledWeatherSources() { return this.sources; }
  async saveSnapshotIfNewer(candidate) {
    const current = this.lastSnapshots.get(candidate.rtId);
    if (current && current.sourceUpdatedAt >= candidate.sourceUpdatedAt) {
      return { snapshot: current, updated: false };
    }
    this.lastSnapshots.set(candidate.rtId, candidate);
    this.snapshots.push(candidate);
    return { snapshot: candidate, updated: true };
  }
  async listReviewedWeatherRules(rtId) {
    return this.rules.filter((item) => item.rtId === rtId);
  }
  async createSuggestionsIfMissing(suggestions) {
    let created = 0;
    for (const item of suggestions) {
      if (!this.suggestions.has(item.suggestionId)) {
        this.suggestions.set(item.suggestionId, item);
        created += 1;
      }
    }
    return created;
  }
  async listSuggestionsForOperator(operatorUid, options) {
    this.operatorLookups.push({ operatorUid, options });
    return [...this.suggestions.values()];
  }
  async getLastValidSnapshotForOperator(operatorUid) {
    this.operatorLookups.push({ operatorUid, snapshot: true });
    return this.lastSnapshots.get('rt-a') ?? null;
  }
  async getLastValidSnapshotForRt(rtId) {
    return this.lastSnapshots.get(rtId) ?? null;
  }
}

function setup(options = {}) {
  const repository = options.repository ?? new FakeRepository(options.repositoryOptions);
  const requestedSources = [];
  const service = new WeatherSuggestionService(repository, {
    clock: () => new Date(NOW),
    fetchPayload: async (item) => {
      requestedSources.push(item.sourceId);
      if (options.fetchError) throw options.fetchError;
      return options.payload ?? payload();
    },
  });
  return { repository, service, requestedSources };
}

test('BMKG normalization requires configured paths and emits only a deterministic scoped snapshot', () => {
  const result = normalizeBmkgSnapshot(source(), payload(), NOW);
  assert.deepEqual(Object.keys(result).sort(), [
    'fetchedAt', 'id', 'rainfallMm', 'rtId', 'source', 'sourceFingerprint', 'sourceUpdatedAt',
  ]);
  assert.equal(result.source, 'BMKG');
  assert.equal(result.rtId, 'rt-a');
  assert.equal(result.rainfallMm, 32.5);
  assert.equal(result.sourceUpdatedAt.toISOString(), SOURCE_UPDATED_AT.toISOString());
  assert.equal(result.fetchedAt.toISOString(), NOW.toISOString());
  assert.match(result.id, /^[a-f0-9]{40}$/u);
  assert.equal(normalizeBmkgSnapshot(source(), payload(), NOW).id, result.id);
  assert.throws(() => normalizeBmkgSnapshot(source(), { data: [] }, NOW), {
    code: 'failed-precondition',
  });
});

test('configured fresh weather creates an idempotent suggestion only, never an active task', async () => {
  const { repository, service } = setup();
  const first = await service.syncConfiguredSources();
  const replay = await service.syncConfiguredSources();
  assert.deepEqual(first, {
    sourcesScanned: 1, snapshotsUpdated: 1, suggestionsCreated: 1, skipped: 0, failed: 0,
  });
  assert.deepEqual(replay, {
    sourcesScanned: 1, snapshotsUpdated: 0, suggestionsCreated: 0, skipped: 1, failed: 0,
  });
  assert.equal(repository.snapshots.length, 1);
  assert.equal(repository.suggestions.size, 1);
  const [suggestion] = repository.suggestions.values();
  assert.equal(suggestion.state, 'SUGGESTED');
  assert.equal(suggestion.source, 'BMKG');
  assert.deepEqual(suggestion.recommendedTemplateVersions, [
    { templateId: 'home-check', version: 2 },
  ]);
  assert.deepEqual(repository.activeCampaigns, []);
});

test('a fetch failure retains the last valid snapshot and produces no suggestion', async () => {
  const previous = normalizeBmkgSnapshot(source(), payload({
    rainfallMm: 10,
    sourceUpdatedAt: '2026-10-04T06:00:00.000Z',
  }), new Date('2026-10-04T07:00:00.000Z'));
  const { repository, service } = setup({
    repositoryOptions: { lastSnapshots: { 'rt-a': previous } },
    fetchError: new Error('upstream detail must not escape'),
  });
  const result = await service.syncConfiguredSources();
  assert.equal(result.failed, 1);
  assert.equal(repository.snapshots.length, 0);
  assert.equal(repository.lastSnapshots.get('rt-a').id, previous.id);
  assert.equal(repository.suggestions.size, 0);
});

test('an older snapshot from a replaced source mapping cannot drive new suggestions', async () => {
  const previous = normalizeBmkgSnapshot(source(), payload({ rainfallMm: 42 }), NOW);
  const changedSource = source({
    endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1002',
  });
  const { repository, service } = setup({
    repositoryOptions: { sources: [changedSource], lastSnapshots: { 'rt-a': previous } },
  });
  const result = await service.syncConfiguredSources();
  assert.equal(result.snapshotsUpdated, 0);
  assert.equal(result.suggestionsCreated, 0);
  assert.equal(repository.snapshots.length, 0);
  assert.equal(repository.suggestions.size, 0);
  assert.equal(repository.lastSnapshots.get('rt-a').sourceFingerprint, previous.sourceFingerprint);
});

test('malformed and stale BMKG data cannot replace the last valid snapshot or create suggestions', async () => {
  const previous = normalizeBmkgSnapshot(source(), payload({
    rainfallMm: 10,
    sourceUpdatedAt: '2026-10-04T06:00:00.000Z',
  }), new Date('2026-10-04T07:00:00.000Z'));
  const malformed = setup({ payload: { data: [] } });
  const malformedResult = await malformed.service.syncConfiguredSources();
  assert.equal(malformedResult.failed, 1);
  assert.equal(malformed.repository.snapshots.length, 0);
  assert.equal(malformed.repository.suggestions.size, 0);

  const stale = setup({
    repositoryOptions: { lastSnapshots: { 'rt-a': previous } },
    payload: payload({ sourceUpdatedAt: '2026-10-01T00:00:00.000Z' }),
  });
  const staleResult = await stale.service.syncConfiguredSources();
  assert.equal(staleResult.skipped, 1);
  assert.equal(stale.repository.snapshots.length, 0);
  assert.equal(stale.repository.lastSnapshots.get('rt-a').id, previous.id);
  assert.equal(stale.repository.suggestions.size, 0);
});

test('fetch latency cannot make a stale forecast look fresh', async () => {
  const repository = new FakeRepository({ sources: [source({ maximumAgeSeconds: 86400 })] });
  let clockCalls = 0;
  const service = new WeatherSuggestionService(repository, {
    clock: () => clockCalls++ === 0 ? new Date(NOW) : new Date(NOW.getTime() + 2 * 86400 * 1000),
    fetchPayload: async () => payload(),
  });
  const result = await service.syncConfiguredSources();
  assert.deepEqual(result, {
    sourcesScanned: 1, snapshotsUpdated: 0, suggestionsCreated: 0, skipped: 1, failed: 0,
  });
  assert.equal(repository.snapshots.length, 0);
  assert.equal(repository.suggestions.size, 0);
});

test('unreviewed or malformed weather rules generate no suggestions', async () => {
  const { repository, service } = setup({
    repositoryOptions: { rules: [
      rule({ reviewStatus: 'pending' }),
      rule({ suggestedTemplateVersions: [] }),
      rule({ minimumRainfallMm: -1 }),
    ] },
  });
  const result = await service.syncConfiguredSources();
  assert.equal(result.snapshotsUpdated, 1);
  assert.equal(result.suggestionsCreated, 0);
  assert.equal(repository.suggestions.size, 0);
});

test('the scheduled pipeline has no default source, location, or rainfall threshold', async () => {
  const repository = new FakeRepository({ sources: [], rules: [] });
  const { service, requestedSources } = setup({ repository });
  const result = await service.syncConfiguredSources();
  assert.deepEqual(result, {
    sourcesScanned: 0, snapshotsUpdated: 0, suggestionsCreated: 0, skipped: 0, failed: 0,
  });
  assert.deepEqual(requestedSources, []);
  assert.equal(repository.snapshots.length, 0);
});

test('last valid snapshot is returned with minimal fields through server-derived RT scope', async () => {
  const { repository, service } = setup();
  await service.syncConfiguredSources();
  const operatorResult = await service.getLastValidWeatherSnapshotForOperator(AUTH, {});
  assert.deepEqual(Object.keys(operatorResult.snapshot).sort(), [
    'communityId', 'fetchedAt', 'id', 'maximumAgeSeconds', 'rainfallMm',
    'source', 'sourceUpdatedAt',
  ]);
  assert.equal(operatorResult.snapshot.communityId, 'rt-a');
  assert.equal(operatorResult.snapshot.source, 'BMKG');
  assert.equal(operatorResult.snapshot.rainfallMm, 32.5);
  assert.equal(operatorResult.snapshot.sourceUpdatedAt, SOURCE_UPDATED_AT.toISOString());
  assert.equal(repository.operatorLookups.at(-1).operatorUid, AUTH.operatorUid);

  const residentResult = await service.getLastValidWeatherSnapshotForRt('rt-a');
  assert.equal(residentResult.snapshot.communityId, 'rt-a');
  assert.equal(
    (await service.getLastValidWeatherSnapshotForRt('rt-missing')).snapshot,
    null,
  );
  await assert.rejects(service.getLastValidWeatherSnapshotForOperator({
    operatorUid: 'resident', signInProvider: 'anonymous',
  }, {}), { code: 'permission-denied' });
  await assert.rejects(service.getLastValidWeatherSnapshotForOperator(AUTH, {
    communityId: 'rt-other',
  }), { code: 'invalid-argument' });
});

test('suggestion listing requires a password-authenticated operator and rejects client scope', async () => {
  const { repository, service } = setup();
  await service.syncConfiguredSources();
  const result = await service.listWeatherSuggestions(AUTH, {});
  assert.equal(result.suggestions.length, 1);
  assert.equal(repository.operatorLookups[0].operatorUid, AUTH.operatorUid);
  await assert.rejects(service.listWeatherSuggestions({
    operatorUid: 'resident', signInProvider: 'anonymous',
  }, {}), { code: 'permission-denied' });
  await assert.rejects(service.listWeatherSuggestions(AUTH, { rtId: 'rt-other' }), {
    code: 'invalid-argument',
  });
});
