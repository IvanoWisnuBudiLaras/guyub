const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { hashJoinCode } = require('../src/resident_session_service');

const PROJECT_ID = 'demo-guyub-functions';
const REGION = 'asia-southeast2';
const HOST = '127.0.0.1';
const PORTS = { auth: 9099, functions: 5001, firestore: 8080 };
const FIRESTORE_BASE = `http://${HOST}:${PORTS.firestore}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const AUTH_BASE = `http://${HOST}:${PORTS.auth}/identitytoolkit.googleapis.com/v1`;

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
  try { payload = text ? JSON.parse(text) : {}; } catch (_) {}
  return { status: response.status, body: payload };
}

async function createAccount({ anonymous = false } = {}) {
  const number = crypto.randomUUID();
  const body = { returnSecureToken: true };
  if (!anonymous) {
    body.email = `resident-proposal-${number}@example.invalid`;
    body.password = 'test-password-123';
  }
  const result = await request(
    'POST', `${AUTH_BASE}/accounts:signUp?key=fake-api-key`, { body },
  );
  assert.equal(result.status, 200, JSON.stringify(result.body));
  return result.body;
}

function documentUrl(collection, id) {
  return `${FIRESTORE_BASE}/${collection}/${encodeURIComponent(id)}`;
}

function fields(record) {
  const result = {};
  for (const [key, value] of Object.entries(record)) {
    if (typeof value === 'string') result[key] = { stringValue: value };
    else if (typeof value === 'boolean') result[key] = { booleanValue: value };
    else if (Number.isInteger(value)) result[key] = { integerValue: String(value) };
    else if (value instanceof Date) result[key] = { timestampValue: value.toISOString() };
  }
  return result;
}

async function seedDocument(collection, id, record) {
  const result = await request('PATCH', documentUrl(collection, id), {
    token: 'owner', body: { fields: fields(record) },
  });
  assert.equal(result.status, 200, JSON.stringify(result.body));
}

async function seedOperator(uid, rtId) {
  await seedDocument('operators', uid, { rtId, role: 'KETUA_RT_RW', active: true });
}

async function seedCommunity(rtId, joinCode) {
  await seedDocument('rt_communities', rtId, {
    displayName: `Komunitas ${rtId}`,
    rtLabel: 'RT Uji',
    joinCodeHash: hashJoinCode(joinCode),
    joinCodeActive: true,
  });
}

async function seedApprovedTemplate(templateId = 'safe_household_prep', version = 1) {
  await seedDocument('task_templates', `${templateId}_v${version}`, {
    templateId,
    version,
    title: 'Persiapan rumah tangga',
    category: 'HOUSEHOLD_PREPARATION',
    coreInstruction: 'Simpan dokumen penting dalam wadah kedap air.',
    safetyInstruction: 'Jangan mendekati air banjir atau instalasi listrik basah.',
    estimatedDurationMinutes: 30,
    enabled: true,
    reviewStatus: 'approved',
    reviewedBy: 'trusted-reviewer',
    reviewedAt: new Date(),
  });
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

function randomRequestId() {
  return crypto.randomBytes(32).toString('base64url');
}

function assertError(response, status) {
  assert.notEqual(response.status, 200, JSON.stringify(response.body));
  assert.equal(response.body.error.status, status, JSON.stringify(response.body));
}

async function createResident(joinCode, nickname) {
  const response = await callFunction('createResidentSession', {
    joinCode,
    nickname,
    requestId: randomRequestId(),
  });
  assert.equal(response.status, 200, JSON.stringify(response.body));
  return response.body.result;
}

async function readDocument(collection, id) {
  return request('GET', documentUrl(collection, id), { token: 'owner' });
}

async function listRtCampaigns(rtId) {
  return request('POST', `${FIRESTORE_BASE}:runQuery`, {
    token: 'owner',
    body: {
      structuredQuery: {
        from: [{ collectionId: 'task_campaigns' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'rtId' },
            op: 'EQUAL',
            value: { stringValue: rtId },
          },
        },
      },
    },
  });
}

test('resident proposal submission, RT queue, safe dismissal, isolation and no direct campaign creation', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-proposal-a-${suffix}`;
  const rtB = `rt-proposal-b-${suffix}`;
  const codeA = `PA${suffix.slice(0, 14).toUpperCase()}`;
  const codeB = `PB${suffix.slice(0, 14).toUpperCase()}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  const anonymousOperator = await createAccount({ anonymous: true });
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtB);
  await seedOperator(anonymousOperator.localId, rtA);
  await seedCommunity(rtA, codeA);
  await seedCommunity(rtB, codeB);

  const residentA = await createResident(codeA, 'Rani');
  const residentSameRt = await createResident(codeA, 'Budi');
  const residentB = await createResident(codeB, 'Tini');
  const requestId = randomRequestId();
  const submitPayload = {
    sessionToken: residentA.sessionToken,
    requestId,
    title: 'Bersihkan saluran drainase',
    description: 'Usul agar warga masuk ke drainase dan mengangkat sampah dari dalam saluran.',
    category: 'ENVIRONMENTAL_CLEANUP',
    locationReference: 'COMMUNITY_GENERAL_AREA',
  };
  const [submitted, concurrentReplay] = await Promise.all([
    callFunction('submitResidentProposal', submitPayload),
    callFunction('submitResidentProposal', submitPayload),
  ]);
  assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
  assert.equal(concurrentReplay.status, 200, JSON.stringify(concurrentReplay.body));
  const proposal = submitted.body.result;
  assert.equal(proposal.state, 'SUBMITTED');
  assert.equal(proposal.description, submitPayload.description);
  assert.equal(proposal.locationReference, 'COMMUNITY_GENERAL_AREA');
  assert.equal(proposal.proposalId, concurrentReplay.body.result.proposalId);
  assert.equal('residentId' in proposal, false);
  assert.equal('rtId' in proposal, false);

  const changedReplay = await callFunction('submitResidentProposal', {
    ...submitPayload,
    description: 'Permintaan berbeda dengan ID yang sama.',
  });
  assertError(changedReplay, 'ALREADY_EXISTS');
  for (const forged of [
    { ...submitPayload, residentId: residentSameRt.residentId },
    { ...submitPayload, rtId: rtB },
    { ...submitPayload, operatorUid: operatorA.localId },
  ]) {
    assertError(await callFunction('submitResidentProposal', forged), 'INVALID_ARGUMENT');
  }
  assertError(await callFunction('submitResidentProposal', {
    ...submitPayload,
    sessionToken: residentB.sessionToken,
    requestId: randomRequestId(),
    rtId: rtA,
  }), 'INVALID_ARGUMENT');

  for (const description of [
    '-6.200123, 106.816456',
    '-6.2, 106.8',
    String.raw`7°45'22"S, 110°22'05"E`,
    String.raw`7° 45′ 22″ S; 110° 22′ 05″ E`,
    String.raw`S 7° 45′ 22″; E 110° 22′ 05″`,
    String.raw`LS 7° 45′ 22″, BT 110° 22′ 05″`,
    String.raw`7 45 22 S, 110 22 05 E`,
    String.raw`S 7 45 22, E 110 22 05`,
    String.raw`S 7° 45.5', E 110° 22.5'`,
    String.raw`N 0° 45′ 22″, W 100° 22′ 05″`,
    String.raw`7°45.366′S 110°22.083′E`,
    'NIK 3175010101900001',
    'NIK 1234/5678/9012/3456',
    'Hubungi 0812-3456-7890',
    'Hubungi 0812/3456/7890',
    'Alamat Jalan Mawar No. 12',
  ]) {
    assertError(await callFunction('submitResidentProposal', {
      ...submitPayload,
      requestId: randomRequestId(),
      description,
    }), 'INVALID_ARGUMENT');
  }
  assertError(await callFunction('submitResidentProposal', {
    ...submitPayload,
    requestId: randomRequestId(),
    category: 'EMERGENCY_RESPONSE',
  }), 'INVALID_ARGUMENT');
  assertError(await callFunction('submitResidentProposal', {
    ...submitPayload,
    requestId: randomRequestId(),
    locationReference: '-6.2, 106.8',
  }), 'INVALID_ARGUMENT');

  const secondProposalResponse = await callFunction('submitResidentProposal', {
    sessionToken: residentSameRt.sessionToken,
    requestId: randomRequestId(),
    title: 'Laporan genangan',
    description: 'Terdapat genangan di area bersama.',
    category: 'SAFE_VISUAL_INSPECTION',
    locationReference: null,
  });
  assert.equal(secondProposalResponse.status, 200, JSON.stringify(secondProposalResponse.body));
  const fromOtherRt = await callFunction('submitResidentProposal', {
    sessionToken: residentB.sessionToken,
    requestId: randomRequestId(),
    title: 'Laporan RT lain',
    description: 'Genangan terlihat di area umum.',
    category: 'SAFE_VISUAL_INSPECTION',
  });
  assert.equal(fromOtherRt.status, 200, JSON.stringify(fromOtherRt.body));

  assertError(await callFunction('listResidentProposals', {}), 'PERMISSION_DENIED');
  assertError(await callFunction('listResidentProposals', {}, anonymousOperator.idToken), 'PERMISSION_DENIED');
  const queueA = await callFunction('listResidentProposals', {}, operatorA.idToken);
  assert.equal(queueA.status, 200, JSON.stringify(queueA.body));
  assert.deepEqual(queueA.body.result.items.map((item) => item.proposalId).sort(), [
    proposal.proposalId,
    secondProposalResponse.body.result.proposalId,
  ].sort());
  assert.equal(queueA.body.result.items.find((item) => item.proposalId === proposal.proposalId).nickname,
    'Rani');
  assert.equal(queueA.body.result.items.every((item) => item.state === 'SUBMITTED'), true);
  assert.equal(queueA.body.result.items.some((item) => 'residentId' in item || 'rtId' in item), false);
  const queueB = await callFunction('listResidentProposals', {}, operatorB.idToken);
  assert.equal(queueB.status, 200, JSON.stringify(queueB.body));
  assert.deepEqual(queueB.body.result.items.map((item) => item.proposalId), [fromOtherRt.body.result.proposalId]);

  const reviewPayload = {
    proposalId: proposal.proposalId,
    decision: 'DISMISSED',
    commandId: randomRequestId(),
  };
  assertError(await callFunction('reviewResidentProposal', reviewPayload, operatorB.idToken),
    'PERMISSION_DENIED');
  assertError(await callFunction('reviewResidentProposal', {
    ...reviewPayload,
    decision: 'MAPPED_TO_SAFE_TEMPLATE',
  }, operatorA.idToken), 'INVALID_ARGUMENT');
  const reviews = await Promise.all([
    callFunction('reviewResidentProposal', reviewPayload, operatorA.idToken),
    callFunction('reviewResidentProposal', reviewPayload, operatorA.idToken),
  ]);
  assert.ok(reviews.every((item) => item.status === 200), JSON.stringify(reviews));
  assert.ok(reviews.every((item) => item.body.result.state === 'DISMISSED'));
  const differentReviewCommand = await callFunction('reviewResidentProposal', {
    ...reviewPayload,
    commandId: randomRequestId(),
  }, operatorA.idToken);
  assertError(differentReviewCommand, 'FAILED_PRECONDITION');
  const afterReview = await callFunction('listResidentProposals', {}, operatorA.idToken);
  assert.equal(afterReview.body.result.items.some((item) => item.proposalId === proposal.proposalId), false);

  const proposalDoc = await readDocument('resident_proposals', proposal.proposalId);
  assert.equal(proposalDoc.status, 200, JSON.stringify(proposalDoc.body));
  const stored = proposalDoc.body.fields;
  assert.equal(stored.state.stringValue, 'DISMISSED');
  assert.equal(stored.reviewDecision.stringValue, 'DISMISSED');
  assert.equal(stored.rtId.stringValue, rtA);
  assert.equal(stored.residentId.stringValue, residentA.residentId);
  assert.equal(stored.description.stringValue, submitPayload.description);
  assert.equal(JSON.stringify(stored).includes(residentA.sessionToken), false);
  assert.equal(JSON.stringify(stored).includes(requestId), false);
  for (const forbidden of [
    'nik', 'fullAddress', 'address', 'latitude', 'longitude', 'gps', 'phone',
    'sessionToken', 'requestId', 'campaignId', 'taskId', 'active',
  ]) {
    assert.equal(Object.keys(stored).some((key) => key.toLowerCase().includes(forbidden.toLowerCase())),
      false, `forbidden proposal field ${forbidden}`);
  }
  const audit = await readDocument(
    'resident_proposal_audit_events', `${proposal.proposalId}_dismissed`,
  );
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.action.stringValue, 'RESIDENT_PROPOSAL_DISMISSED');
  assert.equal(audit.body.fields.actorUid.stringValue, operatorA.localId);
  const campaigns = await listRtCampaigns(rtA);
  assert.equal(campaigns.status, 200, JSON.stringify(campaigns.body));
  assert.equal(campaigns.body.some((row) => row.document != null), false);

  for (const collection of ['resident_proposals', 'resident_proposal_audit_events']) {
    const directRead = await request('GET', documentUrl(collection, proposal.proposalId), {
      token: operatorA.idToken,
    });
    assert.equal(directRead.status, 403, `${collection} direct read was allowed`);
    const directWrite = await request('PATCH', documentUrl(collection, `forged-${suffix}`), {
      token: operatorA.idToken,
      body: { fields: fields({ proposalId: `forged-${suffix}`, state: 'SUBMITTED', rtId: rtB }) },
    });
    assert.equal(directWrite.status, 403, `${collection} direct write was allowed`);
  }
});


test('resident proposal maps only to safe DRAFT and activation remains separate', async () => {
  const suffix = crypto.randomUUID().replaceAll('-', '');
  const rtA = `rt-map-a-${suffix}`;
  const rtB = `rt-map-b-${suffix}`;
  const codeA = `MA${suffix.slice(0, 14).toUpperCase()}`;
  const codeB = `MB${suffix.slice(0, 14).toUpperCase()}`;
  const operatorA = await createAccount();
  const operatorB = await createAccount();
  await seedOperator(operatorA.localId, rtA);
  await seedOperator(operatorB.localId, rtB);
  await seedCommunity(rtA, codeA);
  await seedCommunity(rtB, codeB);
  await seedApprovedTemplate();
  const resident = await createResident(codeA, 'Rani');
  const submitted = await callFunction('submitResidentProposal', {
    sessionToken: resident.sessionToken, requestId: randomRequestId(),
    title: 'Masuk ke drainase',
    description: 'Usul agar warga masuk ke drainase dan mengangkat sampah dari dalam.',
    category: 'ENVIRONMENTAL_CLEANUP', locationReference: 'COMMUNITY_GENERAL_AREA',
  });
  assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
  const proposalId = submitted.body.result.proposalId;
  const mapPayload = {
    proposalId, templateId: 'safe_household_prep', version: 1,
    deadline: new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString(),
    locationReference: 'COMMUNITY_GENERAL_AREA', commandId: randomRequestId(),
  };
  const results = await Promise.all([
    callFunction('mapResidentProposalToDraft', mapPayload, operatorA.idToken),
    callFunction('mapResidentProposalToDraft', mapPayload, operatorA.idToken),
  ]);
  assert.ok(results.every((r) => r.status === 200), JSON.stringify(results));
  const mapped = results[0].body.result;
  const campaign = mapped.campaign;
  assert.equal(mapped.proposal.state, 'MAPPED_TO_SAFE_TEMPLATE');
  assert.equal(campaign.status, 'DRAFT');
  assert.equal(campaign.activatedAt, null);
  assert.equal(campaign.templateSnapshot.coreInstruction, 'Simpan dokumen penting dalam wadah kedap air.');
  assert.equal(JSON.stringify(campaign).includes('Masuk ke drainase'), false);
  assert.equal(JSON.stringify(campaign).includes('warga masuk ke drainase'), false);
  assert.equal(results[1].body.result.campaign.campaignId, campaign.campaignId);
  assert.deepEqual((await callFunction('listResidentProposals', {}, operatorA.idToken)).body.result.items, []);
  const before = await callFunction('listResidentActiveTasks', { sessionToken: resident.sessionToken });
  assert.deepEqual(before.body.result.items, []);
  assertError(await callFunction('mapResidentProposalToDraft', mapPayload, operatorB.idToken), 'PERMISSION_DENIED');
  assertError(await callFunction('mapResidentProposalToDraft', { ...mapPayload, commandId: randomRequestId() }, operatorA.idToken), 'FAILED_PRECONDITION');
  assertError(await callFunction('mapResidentProposalToDraft', { ...mapPayload, freeTextInstruction: 'dangerous' }, operatorA.idToken), 'INVALID_ARGUMENT');
  const audit = await readDocument('resident_proposal_audit_events', `${proposalId}_mapped`);
  assert.equal(audit.status, 200, JSON.stringify(audit.body));
  assert.equal(audit.body.fields.action.stringValue, 'RESIDENT_PROPOSAL_MAPPED_TO_SAFE_TEMPLATE');
  assert.equal(JSON.stringify(audit.body.fields).includes('drainase'), false);
  assert.equal(JSON.stringify(audit.body.fields).includes(mapPayload.commandId), false);
  const campaignDoc = await readDocument('task_campaigns', campaign.campaignId);
  assert.equal(campaignDoc.body.fields.status.stringValue, 'DRAFT');
  assert.equal(campaignDoc.body.fields.sourceProposalId.stringValue, proposalId);
  assert.equal(campaignDoc.body.fields.templateSnapshot.mapValue.fields.coreInstruction.stringValue,
    'Simpan dokumen penting dalam wadah kedap air.');
  const activation = await callFunction('activateTaskCampaign', {
    campaignId: campaign.campaignId, commandId: randomRequestId(),
  }, operatorA.idToken);
  assert.equal(activation.status, 200, JSON.stringify(activation.body));
  assert.equal(activation.body.result.status, 'ACTIVE');
  const after = await callFunction('listResidentActiveTasks', { sessionToken: resident.sessionToken });
  assert.equal(after.body.result.items.length, 1);
});
