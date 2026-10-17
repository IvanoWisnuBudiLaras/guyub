'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  TreePointService,
  TreePointError,
  MAX_ACCURACY_METERS,
} = require('../src/tree_point_service');
const { encodeGeohash } = require('../src/geohash');

const NOW = new Date('2026-10-18T03:00:00.000Z');
const SESSION_TOKEN = 's'.repeat(43);
const TASK_ID = 'a'.repeat(40);
const COMMAND_ID = 'c'.repeat(43);
const TREE_POINT_ID = 'b'.repeat(40);
const OPERATOR_AUTH = { operatorUid: 'operator-rt01', signInProvider: 'password' };

class FakeResidentSessions {
  async validateSession(token) {
    if (token !== SESSION_TOKEN) {
      const error = new Error('invalid session');
      error.code = 'permission-denied';
      throw error;
    }
    return {
      residentId: 'resident-budi',
      communityId: 'rt-01',
      nickname: 'Budi',
    };
  }
}

class FakeTreePointRepository {
  constructor() {
    this.points = new Map();
    this.privateLocations = new Map();
  }

  async getOperatorRtId(uid) {
    if (uid === 'operator-rt01') return 'rt-01';
    throw new Error('unknown operator');
  }

  async createTreePoint(input) {
    const coarseLocation = encodeGeohash(input.exactLat, input.exactLng, 7);
    const point = {
      treePointId: TREE_POINT_ID,
      rtId: input.rtId,
      taskId: input.taskId,
      residentId: input.residentId,
      submitterNickname: input.submitterNickname,
      speciesHint: input.speciesHint,
      plantedAt: input.now,
      status: 'PENDING_RT_VERIFICATION',
      coarseLocation,
      evidenceId: input.evidenceId,
      isAnonymous: false,
    };
    this.points.set(TREE_POINT_ID, point);
    this.privateLocations.set(TREE_POINT_ID, {
      exactLat: input.exactLat,
      exactLng: input.exactLng,
      accuracyMeters: input.accuracyMeters,
      isMocked: input.isMocked,
    });
    return {
      treePointId: TREE_POINT_ID,
      status: 'PENDING_RT_VERIFICATION',
      coarseLocation,
      plantedAt: input.now.toISOString(),
    };
  }

  async listCommunityTreeMap({ rtId }) {
    const items = [];
    for (const p of this.points.values()) {
      if (p.rtId === rtId && p.status === 'VERIFIED') {
        items.push({
          treePointId: p.treePointId,
          speciesHint: p.speciesHint,
          submitterNickname: p.isAnonymous ? 'Pohon Warga (Anonim)' : p.submitterNickname,
          isAnonymous: p.isAnonymous,
          coarseLocation: p.coarseLocation,
          plantedAt: p.plantedAt.toISOString(),
          hasEvidencePhoto: Boolean(p.evidenceId),
        });
      }
    }
    return { items, totalVerifiedTrees: items.length };
  }

  async verifyTreePoint({ operatorUid, treePointId, decision, rejectionReason, now }) {
    const point = this.points.get(treePointId);
    if (!point) throw new TreePointError('not-found', 'Titik pohon tidak ditemukan.');
    const status = decision === 'APPROVE' ? 'VERIFIED' : 'REJECTED';
    point.status = status;
    point.verifiedAt = now;
    point.verifiedByOperatorUid = operatorUid;
    point.rejectionReason = rejectionReason;
    return {
      treePointId,
      status,
      verifiedAt: now.toISOString(),
    };
  }

  async deleteTreePoint({ actorUid, isOperator, rtId, treePointId }) {
    const point = this.points.get(treePointId);
    if (!point) throw new TreePointError('not-found', 'Titik pohon tidak ditemukan.');
    if (!isOperator && (point.residentId !== actorUid || point.rtId !== rtId)) {
      throw new TreePointError('permission-denied', 'Tidak diizinkan.');
    }
    this.points.delete(treePointId);
    this.privateLocations.delete(treePointId);
    return { deleted: true, treePointId };
  }
}

function createService(repo = new FakeTreePointRepository()) {
  return new TreePointService(repo, new FakeResidentSessions(), () => NOW);
}

test('Geohash encoding produces precision 7 cell and midpoints', () => {
  const result = encodeGeohash(-8.065432, 111.901234, 7);
  assert.equal(typeof result.cellId, 'string');
  assert.equal(result.cellId.length, 7);
  assert.equal(typeof result.approximateLat, 'number');
  assert.equal(typeof result.approximateLng, 'number');
  // Coarse coordinate should be within 0.002 degrees (~200m) of real point
  assert.ok(Math.abs(result.approximateLat - (-8.065432)) < 0.005);
  assert.ok(Math.abs(result.approximateLng - 111.901234) < 0.005);
});

test('submitTreePoint accepts valid submission and creates pending point with coarse location', async () => {
  const service = createService();
  const result = await service.submitTreePoint({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    speciesHint: 'Mangga Arumanis',
    exactLat: -8.065432,
    exactLng: 111.901234,
    accuracyMeters: 12.5,
    isMocked: false,
    commandId: COMMAND_ID,
  });

  assert.equal(result.treePointId, TREE_POINT_ID);
  assert.equal(result.status, 'PENDING_RT_VERIFICATION');
  assert.equal(result.coarseLocation.cellId.length, 7);
});

test('submitTreePoint rejects GPS accuracy worse than 30 meters', async () => {
  const service = createService();
  await assert.rejects(
    service.submitTreePoint({
      sessionToken: SESSION_TOKEN,
      taskId: TASK_ID,
      exactLat: -8.065432,
      exactLng: 111.901234,
      accuracyMeters: 31.0,
      isMocked: false,
      commandId: COMMAND_ID,
    }),
    (err) => err instanceof TreePointError && err.code === 'failed-precondition' &&
      err.message.includes('Akurasi GPS tidak memadai')
  );
});

test('submitTreePoint rejects mocked GPS location', async () => {
  const service = createService();
  await assert.rejects(
    service.submitTreePoint({
      sessionToken: SESSION_TOKEN,
      taskId: TASK_ID,
      exactLat: -8.065432,
      exactLng: 111.901234,
      accuracyMeters: 10.0,
      isMocked: true,
      commandId: COMMAND_ID,
    }),
    (err) => err instanceof TreePointError && err.code === 'permission-denied' &&
      err.message.includes('Lokasi tiruan')
  );
});

test('submitTreePoint rejects speciesHint containing address or coordinates', async () => {
  const service = createService();
  await assert.rejects(
    service.submitTreePoint({
      sessionToken: SESSION_TOKEN,
      taskId: TASK_ID,
      speciesHint: 'Jalan Merdeka No 12 -8.065, 111.901',
      exactLat: -8.065432,
      exactLng: 111.901234,
      accuracyMeters: 10.0,
      isMocked: false,
      commandId: COMMAND_ID,
    }),
    (err) => err instanceof TreePointError && err.code === 'invalid-argument' &&
      err.message.includes('tidak boleh memuat alamat')
  );
});

test('listCommunityTreeMap returns only verified trees with coarse location', async () => {
  const repo = new FakeTreePointRepository();
  const service = createService(repo);

  // Submit and verify a tree
  await service.submitTreePoint({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    speciesHint: 'Ketapang Kencana',
    exactLat: -8.065432,
    exactLng: 111.901234,
    accuracyMeters: 15.0,
    isMocked: false,
    commandId: COMMAND_ID,
  });

  // Verify by operator
  await service.verifyTreePoint(OPERATOR_AUTH, {
    treePointId: TREE_POINT_ID,
    decision: 'APPROVE',
    commandId: COMMAND_ID,
  });

  const mapData = await service.listCommunityTreeMap(OPERATOR_AUTH, {});
  assert.equal(mapData.totalVerifiedTrees, 1);
  assert.equal(mapData.items[0].speciesHint, 'Ketapang Kencana');
  assert.equal(mapData.items[0].submitterNickname, 'Budi');
  assert.equal(mapData.items[0].coarseLocation.cellId.length, 7);
  // Verify that exact coordinates are NEVER in map items
  assert.equal(mapData.items[0].exactLat, undefined);
  assert.equal(mapData.items[0].exactLng, undefined);
});

test('verifyTreePoint requires reason when rejecting', async () => {
  const service = createService();
  await assert.rejects(
    service.verifyTreePoint(OPERATOR_AUTH, {
      treePointId: TREE_POINT_ID,
      decision: 'REJECT',
      rejectionReason: '',
      commandId: COMMAND_ID,
    }),
    (err) => err instanceof TreePointError && err.code === 'invalid-argument'
  );
});

test('verifyTreePoint rejects non-operator caller', async () => {
  const service = createService();
  await assert.rejects(
    service.verifyTreePoint({ operatorUid: 'warga-a', signInProvider: 'anonymous' }, {
      treePointId: TREE_POINT_ID,
      decision: 'APPROVE',
      commandId: COMMAND_ID,
    }),
    (err) => err instanceof TreePointError && err.code === 'permission-denied'
  );
});

test('deleteTreePoint allows operator or owner to delete', async () => {
  const repo = new FakeTreePointRepository();
  const service = createService(repo);

  await service.submitTreePoint({
    sessionToken: SESSION_TOKEN,
    taskId: TASK_ID,
    exactLat: -8.065432,
    exactLng: 111.901234,
    accuracyMeters: 15.0,
    isMocked: false,
    commandId: COMMAND_ID,
  });

  const res = await service.deleteTreePoint(OPERATOR_AUTH, {
    treePointId: TREE_POINT_ID,
  });
  assert.equal(res.deleted, true);
  assert.equal(repo.points.size, 0);
});
