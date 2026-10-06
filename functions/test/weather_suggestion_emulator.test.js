const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { FirestoreWeatherSuggestionRepository } = require('../src/firestore_weather_suggestion_repository');
const { approvedTemplateFromRecord } = require('../src/task_campaign_service');
const { WeatherSuggestionService } = require('../src/weather_suggestion_service');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, functions: 5001, firestore: 8080 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;
const adminApp = getApps().find((app) => app.name === '[DEFAULT]') ??
  initializeApp({ projectId: PROJECT_ID });
const firestore = getFirestore(adminApp);

async function request(method, url, { token, body } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  const response = await fetch(url, {
    method,
    headers,
    ...(body == null ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let payload = {};
  try { payload = text ? JSON.parse(text) : {}; } catch (_) { payload = {}; }
  return { status: response.status, body: payload };
}

async function createAccount() {
  const number = crypto.randomUUID();
  const result = await request('POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, {
    body: {
      email: `weather-operator-${number}@example.invalid`,
      password: 'test-password-123',
      returnSecureToken: true,
    },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}

function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}

async function seedOperator(uid, rtId) {
  await firestore.collection('operators').doc(uid).set({
    rtId,
    role: 'KETUA_RT_RW',
    active: true,
  });
}

async function callFunction(name, data, idToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(
    `http://${HOST}:${PORTS.functions}/${PROJECT_ID}/${REGION}/${name}`,
    {
      method: 'POST',
      headers,
      body: JSON.stringify({ data }),
    },
  );
  return { status: response.status, body: await response.json() };
}

function sourceRecord(rtId) {
  return {
    rtId,
    source: 'BMKG',
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'trusted-weather-reviewer',
    reviewedAt: new Date(Date.now() - 60 * 60 * 1000),
    endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1001',
    maximumAgeSeconds: 86400,
    normalization: {
      rainfallMmPath: ['data', 0, 'forecast', 'rainfall_mm'],
      sourceUpdatedAtPath: ['data', 0, 'forecast', 'source_updated_at'],
    },
  };
}

function templateRecord({
  templateId = 'home-check', version = 2, enabled = true, reviewStatus = 'approved',
} = {}) {
  return {
    templateId,
    version,
    title: 'Persiapan rumah tangga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting dalam wadah yang mudah dijangkau.',
    safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik yang basah.',
    estimatedDurationMinutes: 30,
    enabled,
    reviewStatus,
    reviewedBy: 'trusted-template-reviewer',
    reviewedAt: new Date(Date.now() - 60 * 60 * 1000),
  };
}

function ruleRecord(rtId, {
  ruleId = 'heavy-rain-preparation', version = 1, minimumRainfallMm = 25,
  templateId = 'home-check', templateVersion = 2, enabled = true, reviewStatus = 'approved',
} = {}) {
  const approvedTemplate = approvedTemplateFromRecord(
    templateRecord({ templateId, version: templateVersion }), templateId, templateVersion,
  );
  return {
    ruleId,
    version,
    rtId,
    enabled,
    reviewStatus,
    reviewedBy: 'trusted-weather-reviewer',
    reviewedAt: new Date(Date.now() - 60 * 60 * 1000),
    minimumRainfallMm,
    suggestedTemplateVersions: [{
      templateId,
      version: templateVersion,
      fingerprint: approvedTemplate?.fingerprint ?? '0'.repeat(64),
    }],
    explanation: 'Tinjau persiapan rumah tangga berdasarkan konteks prakiraan BMKG.',
  };
}

test('BMKG snapshot is stored once, only reviewed rules/templates suggest, and RT operator reads suggestion', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-weather-${suffix}`;
  const account = await createAccount();
  await seedOperator(account.localId, rtId);
  await firestore.collection('task_templates').doc('home-check_v2').set(templateRecord());
  await firestore.collection('task_templates').doc('unsafe-unreviewed_v1').set(
    templateRecord({
      templateId: 'unsafe-unreviewed', version: 1, enabled: false, reviewStatus: 'pending',
    }),
  );
  await firestore.collection('weather_sources').doc(rtId).set(sourceRecord(rtId));
  await firestore.collection('weather_rules').doc(`${rtId}_heavy-rain-preparation_v1`).set(
    ruleRecord(rtId),
  );
  await firestore.collection('weather_rules').doc(`${rtId}_unreviewed-template_v1`).set(
    ruleRecord(rtId, {
      ruleId: 'unreviewed-template', templateId: 'unsafe-unreviewed', templateVersion: 1,
    }),
  );

  const repository = new FirestoreWeatherSuggestionRepository(firestore);
  const forecastUpdatedAt = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const service = new WeatherSuggestionService(repository, {
    clock: () => new Date(),
    fetchPayload: async () => ({
      data: [{ forecast: {
        rainfall_mm: 42,
        source_updated_at: forecastUpdatedAt,
      } }],
    }),
  });
  const first = await service.syncConfiguredSources();
  const replay = await service.syncConfiguredSources();
  assert.equal(first.snapshotsUpdated, 1);
  assert.equal(first.suggestionsCreated, 1);
  assert.equal(first.failed, 0);
  assert.equal(replay.snapshotsUpdated, 0);
  assert.equal(replay.suggestionsCreated, 0);

  const suggestions = await firestore.collection('task_suggestions')
    .where('rtId', '==', rtId).get();
  assert.equal(suggestions.size, 1);
  const suggestion = suggestions.docs[0].data();
  assert.equal(suggestion.state, 'SUGGESTED');
  assert.deepEqual(suggestion.recommendedTemplateVersions, [
    { templateId: 'home-check', version: 2 },
  ]);
  assert.deepEqual((await firestore.collection('task_campaigns')
    .where('rtId', '==', rtId).get()).docs, []);

  const read = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(read.status, 200, JSON.stringify(read.body));
  assert.equal(read.body.result.suggestions.length, 1);
  assert.equal(read.body.result.suggestions[0].source, 'BMKG');
  assert.equal(read.body.result.suggestions[0].state, 'SUGGESTED');
  assert.equal(read.body.result.suggestions[0].isStale, false);
  assert.equal('rtId' in read.body.result.suggestions[0], false);
  const operatorSnapshot = await callFunction(
    'getLastValidWeatherSnapshot', {}, account.idToken,
  );
  assert.equal(operatorSnapshot.status, 200, JSON.stringify(operatorSnapshot.body));
  assert.equal(operatorSnapshot.body.result.snapshot.communityId, rtId);
  assert.equal(operatorSnapshot.body.result.snapshot.rainfallMm, 42);
  assert.equal(operatorSnapshot.body.result.snapshot.maximumAgeSeconds, 86400);
  assert.equal('rtId' in operatorSnapshot.body.result.snapshot, false);
  assert.equal('sourceFingerprint' in operatorSnapshot.body.result.snapshot, false);
  const forgedScope = await callFunction(
    'getLastValidWeatherSnapshot', { communityId: `rt-other-${suffix}` }, account.idToken,
  );
  assert.equal(forgedScope.status, 400);

  const ignored = await callFunction('ignoreWeatherSuggestion', {
    suggestionId: suggestion.suggestionId,
  }, account.idToken);
  assert.equal(ignored.status, 200, JSON.stringify(ignored.body));
  assert.deepEqual(ignored.body.result, { ignored: true });
  const ignoredReplay = await callFunction('ignoreWeatherSuggestion', {
    suggestionId: suggestion.suggestionId,
  }, account.idToken);
  assert.equal(ignoredReplay.status, 200, JSON.stringify(ignoredReplay.body));
  assert.deepEqual(ignoredReplay.body.result, { ignored: true });
  const ignoredRecord = await firestore.collection('task_suggestions')
    .doc(suggestion.suggestionId).get();
  assert.equal(ignoredRecord.data().state, 'IGNORED');
  assert.equal(ignoredRecord.data().ignoredByOperatorUid, account.localId);
  assert.equal((await callFunction('listWeatherSuggestions', {}, account.idToken))
    .body.result.suggestions.length, 0);
  const replayAfterIgnore = await service.syncConfiguredSources();
  assert.equal(replayAfterIgnore.failed, 0);
  assert.equal(replayAfterIgnore.suggestionsCreated, 0);
  assert.equal((await firestore.collection('task_suggestions')
    .doc(suggestion.suggestionId).get()).data().state, 'IGNORED');

  const pointerRef = firestore.collection('weather_last_valid_snapshots').doc(rtId);
  const pointerBeforeFailure = (await pointerRef.get()).data();
  const malformedService = new WeatherSuggestionService(repository, {
    clock: () => new Date(),
    fetchPayload: async () => ({ data: [] }),
  });
  const malformedSync = await malformedService.syncConfiguredSources();
  assert.equal(malformedSync.failed, 1);
  assert.equal((await pointerRef.get()).data().snapshotId, pointerBeforeFailure.snapshotId,
    'malformed data must preserve the last valid server snapshot');
  assert.equal((await firestore.collection('task_suggestions')
    .where('rtId', '==', rtId).get()).size, 1);

  const directRead = await request('GET', documentUrl('task_suggestions', suggestions.docs[0].id), {
    token: account.idToken,
  });
  assert.notEqual(directRead.status, 200, 'clients must not read suggestion records directly');
  const directWrite = await request(
    'PATCH', documentUrl('task_suggestions', suggestions.docs[0].id),
    { token: account.idToken, body: { fields: { state: { stringValue: 'ACTIVE' } } } },
  );
  assert.notEqual(directWrite.status, 200, 'clients must not change suggestion state');
  const snapshotRead = await request(
    'GET', documentUrl('weather_snapshots', pointerBeforeFailure.snapshotId),
    { token: account.idToken },
  );
  assert.notEqual(snapshotRead.status, 200, 'clients must not read weather snapshots directly');
  const sourceRead = await request('GET', documentUrl('weather_sources', rtId), {
    token: account.idToken,
  });
  assert.notEqual(sourceRead.status, 200, 'clients must not read BMKG source config directly');
  const ruleRead = await request(
    'GET', documentUrl('weather_rules', `${rtId}_heavy-rain-preparation_v1`),
    { token: account.idToken },
  );
  assert.notEqual(ruleRead.status, 200, 'clients must not read weather rules directly');

  await firestore.collection('weather_rules')
    .doc(`${rtId}_heavy-rain-preparation_v2`).set(ruleRecord(rtId, {
      version: 2,
      enabled: false,
    }));
  const disabledRuleSync = await service.syncConfiguredSources();
  assert.equal(disabledRuleSync.suggestionsCreated, 0);
  const afterDisabledRule = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(afterDisabledRule.status, 200, JSON.stringify(afterDisabledRule.body));
  assert.deepEqual(afterDisabledRule.body.result.suggestions, [],
    'a disabled newer rule must suppress older suggestions instead of falling back');

  await firestore.collection('weather_rules')
    .doc(`${rtId}_heavy-rain-preparation_v2`).update({ enabled: true, minimumRainfallMm: 90 });
  await service.syncConfiguredSources();
  const afterRuleChange = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(afterRuleChange.status, 200, JSON.stringify(afterRuleChange.body));
  assert.deepEqual(afterRuleChange.body.result.suggestions, [],
    'older suggestions must not survive a reviewed rule version change');

  await firestore.collection('weather_rules')
    .doc(`${rtId}_heavy-rain-preparation_v2`).update({ enabled: false });
  await firestore.collection('weather_rules')
    .doc(`${rtId}_heavy-rain-preparation_v3`).set(ruleRecord(rtId, { version: 3 }));
  await firestore.collection('weather_sources').doc(rtId).update({
    endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1002',
    reviewedAt: new Date(),
  });
  const sourceConfigChange = await service.syncConfiguredSources();
  assert.equal(sourceConfigChange.snapshotsUpdated, 1,
    'a reviewed source mapping change can create a new scoped snapshot');
  const afterSourceChange = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(afterSourceChange.status, 200, JSON.stringify(afterSourceChange.body));
  assert.equal(afterSourceChange.body.result.suggestions.length, 1);
  assert.equal(afterSourceChange.body.result.suggestions[0].ruleVersion, 3);

  await firestore.collection('task_templates').doc('home-check_v2').update({
    title: 'Changed without a new approved template version',
  });
  const afterTemplateMutation = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(afterTemplateMutation.status, 200, JSON.stringify(afterTemplateMutation.body));
  assert.deepEqual(afterTemplateMutation.body.result.suggestions, [],
    'same-version template mutation must make the approved rule and suggestions stale');
  const templateMutationSync = await service.syncConfiguredSources();
  assert.equal(templateMutationSync.suggestionsCreated, 0,
    'changed template content must require a newly reviewed rule reference');

  const other = await createAccount();
  await seedOperator(other.localId, `rt-other-${suffix}`);
  const otherRead = await callFunction('listWeatherSuggestions', {}, other.idToken);
  assert.equal(otherRead.status, 200, JSON.stringify(otherRead.body));
  assert.deepEqual(otherRead.body.result.suggestions, []);
  const crossRtIgnore = await callFunction('ignoreWeatherSuggestion', {
    suggestionId: afterSourceChange.body.result.suggestions[0].suggestionId,
  }, other.idToken);
  assert.notEqual(crossRtIgnore.status, 200,
    'operators cannot ignore suggestions outside their RT');
});

test('a newer valid below-threshold snapshot makes the prior suggestion stale', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-weather-superseded-${suffix}`;
  const account = await createAccount();
  await seedOperator(account.localId, rtId);
  await firestore.collection('task_templates').doc('home-check_v2').set(templateRecord());
  await firestore.collection('weather_sources').doc(rtId).set(sourceRecord(rtId));
  await firestore.collection('weather_rules').doc(`${rtId}_heavy-rain-preparation_v1`).set(
    ruleRecord(rtId),
  );

  let rainfallMm = 42;
  let sourceUpdatedAt = new Date(Date.now() - 60 * 60 * 1000);
  const repository = new FirestoreWeatherSuggestionRepository(firestore);
  const scopedRepository = Object.create(repository);
  scopedRepository.listEnabledWeatherSources = async () =>
    (await repository.listEnabledWeatherSources()).filter((source) => source.rtId === rtId);
  const service = new WeatherSuggestionService(scopedRepository, {
    fetchPayload: async () => ({ data: [{ forecast: {
      rainfall_mm: rainfallMm,
      source_updated_at: sourceUpdatedAt.toISOString(),
    } }] }),
  });

  const firstSync = await service.syncConfiguredSources();
  assert.equal(firstSync.suggestionsCreated, 1);
  const pointerRef = firestore.collection('weather_last_valid_snapshots').doc(rtId);
  const priorSnapshotId = (await pointerRef.get()).data().snapshotId;

  rainfallMm = 10;
  sourceUpdatedAt = new Date(Date.now() - 30 * 1000);
  const nextSync = await service.syncConfiguredSources();
  assert.equal(nextSync.snapshotsUpdated, 1);
  assert.equal(nextSync.suggestionsCreated, 0);
  assert.notEqual((await pointerRef.get()).data().snapshotId, priorSnapshotId);

  const read = await callFunction('listWeatherSuggestions', {}, account.idToken);
  assert.equal(read.status, 200, JSON.stringify(read.body));
  assert.equal(read.body.result.suggestions.length, 1);
  assert.equal(read.body.result.suggestions[0].snapshotId, priorSnapshotId);
  assert.equal(read.body.result.suggestions[0].state, 'SUGGESTED');
  assert.equal(read.body.result.suggestions[0].isStale, true);
  assert.deepEqual((await firestore.collection('task_campaigns')
    .where('rtId', '==', rtId).get()).docs, []);
});

test('resident weather snapshot derives its RT from the live session, not client scope', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtId = `rt-resident-weather-${suffix}`;
  const joinCode = `A${suffix.slice(0, 11).toUpperCase()}`;
  await firestore.collection('rt_communities').doc(rtId).set({
    displayName: 'RT Uji Cuaca',
    rtLabel: 'RT Uji',
    joinCodeHash: hashJoinCode(joinCode),
    joinCodeActive: true,
  });
  const snapshotId = crypto.createHash('sha256').update(`snapshot-${suffix}`)
    .digest('hex').slice(0, 40);
  const updatedAt = new Date(Date.now() - 10 * 60 * 1000);
  const snapshotRecord = {
    snapshotId,
    rtId,
    source: 'BMKG',
    sourceFingerprint: 'a'.repeat(64),
    sourceUpdatedAt: updatedAt,
    fetchedAt: updatedAt,
    rainfallMm: 7.5,
    isLastValid: true,
  };
  await firestore.collection('weather_snapshots').doc(snapshotId).set(snapshotRecord);
  await firestore.collection('weather_last_valid_snapshots').doc(rtId).set({
    rtId,
    snapshotId,
    sourceFingerprint: snapshotRecord.sourceFingerprint,
    sourceUpdatedAt: updatedAt,
    fetchedAt: updatedAt,
  });
  const enrollment = await callFunction('createResidentSession', {
    joinCode,
    nickname: 'Warga Cuaca',
    requestId: crypto.randomBytes(32).toString('base64url'),
  });
  assert.equal(enrollment.status, 200, JSON.stringify(enrollment.body));
  const sessionToken = enrollment.body.result.sessionToken;

  const snapshot = await callFunction('getLastValidWeatherSnapshot', { sessionToken });
  assert.equal(snapshot.status, 200, JSON.stringify(snapshot.body));
  assert.equal(snapshot.body.result.snapshot.communityId, rtId);
  assert.equal(snapshot.body.result.snapshot.rainfallMm, 7.5);
  assert.equal('rtId' in snapshot.body.result.snapshot, false);

  const forgedScope = await callFunction('getLastValidWeatherSnapshot', {
    sessionToken,
    communityId: `rt-other-${suffix}`,
  });
  assert.equal(forgedScope.status, 400);
  const invalidSession = await callFunction('getLastValidWeatherSnapshot', {
    sessionToken: 'invalid-session-token',
  });
  assert.equal(invalidSession.status, 403);
});
