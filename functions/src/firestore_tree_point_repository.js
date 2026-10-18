'use strict';

const crypto = require('node:crypto');
const { encodeGeohash } = require('./geohash');
const { TreePointError } = require('./tree_point_service');

const TREE_POINT_COLLECTION = 'tree_points';
const OPERATOR_COLLECTION = 'operators';
const AUDIT_COLLECTION = 'tree_point_audit_events';
const MAX_MAP_TREES = 500;

function fail(code, message) {
  return new TreePointError(code, message);
}

function deny(message = 'Akses titik pohon tidak diizinkan.') {
  return fail('permission-denied', message);
}

function notFound(message = 'Titik pohon tidak ditemukan.') {
  return fail('not-found', message);
}

function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true ||
      !['KETUA_RT_RW', 'PENDAMPING_RT'].includes(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) {
    throw deny();
  }
  return { rtId: data.rtId.trim(), role: data.role };
}

function iso(date) {
  if (date instanceof Date) return date.toISOString();
  if (date && typeof date.toDate === 'function') return date.toDate().toISOString();
  if (typeof date === 'string') return date;
  return null;
}

class FirestoreTreePointRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async getOperatorRtId(operatorUid) {
    const doc = await this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid).get();
    const operator = requireOperator(doc);
    return operator.rtId;
  }

  async createTreePoint(input) {
    const {
      rtId, taskId, residentId, submitterNickname, speciesHint,
      exactLat, exactLng, accuracyMeters, isMocked, evidenceId,
      commandHash, now,
    } = input;

    const treePointId = crypto.createHash('sha256')
      .update(`${rtId}\0${taskId}\0${residentId}\0${commandHash}`)
      .digest('hex')
      .slice(0, 40);

    const coarseLocation = encodeGeohash(exactLat, exactLng, 7);

    const docRef = this.firestore.collection(TREE_POINT_COLLECTION).doc(treePointId);
    const privateLocationRef = docRef.collection('private').doc('location');

    return this.firestore.runTransaction(async (transaction) => {
      const existing = await transaction.get(docRef);
      if (existing.exists) {
        const data = existing.data();
        if (data.commandHash === commandHash && data.residentId === residentId) {
          return {
            treePointId,
            status: data.status,
            coarseLocation: data.coarseLocation,
            plantedAt: iso(data.plantedAt),
          };
        }
        throw fail('already-exists', 'Titik pohon sudah pernah didaftarkan.');
      }

      const mainDoc = {
        treePointId,
        rtId,
        taskId,
        residentId,
        submitterNickname,
        speciesHint: speciesHint ?? null,
        plantedAt: now,
        clientReportedAt: now,
        status: 'PENDING_RT_VERIFICATION',
        rejectionReason: null,
        verifiedByOperatorUid: null,
        verifiedAt: null,
        coarseLocation,
        evidenceId: evidenceId ?? null,
        isAnonymous: false,
        commandHash,
        createdAt: now,
        updatedAt: now,
      };

      const privateDoc = {
        treePointId,
        exactLat,
        exactLng,
        accuracyMeters,
        isMocked,
        recordedAt: now,
      };

      transaction.create(docRef, mainDoc);
      transaction.create(privateLocationRef, privateDoc);

      return {
        treePointId,
        status: 'PENDING_RT_VERIFICATION',
        coarseLocation,
        plantedAt: iso(now),
      };
    });
  }

  async listCommunityTreeMap({ rtId }) {
    const snapshot = await this.firestore.collection(TREE_POINT_COLLECTION)
      .where('rtId', '==', rtId)
      .where('status', '==', 'VERIFIED')
      .limit(MAX_MAP_TREES)
      .get();

    const items = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        treePointId: data.treePointId,
        speciesHint: data.speciesHint ?? null,
        submitterNickname: data.isAnonymous ? 'Pohon Warga (Anonim)' : data.submitterNickname,
        isAnonymous: data.isAnonymous === true,
        coarseLocation: data.coarseLocation,
        plantedAt: iso(data.plantedAt),
        hasEvidencePhoto: Boolean(data.evidenceId),
      };
    });

    return {
      items,
      totalVerifiedTrees: items.length,
    };
  }

  async verifyTreePoint({ operatorUid, treePointId, decision, rejectionReason, commandHash, now }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    const treeRef = this.firestore.collection(TREE_POINT_COLLECTION).doc(treePointId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(`${treePointId}_${decision.toLowerCase()}`);

    return this.firestore.runTransaction(async (transaction) => {
      const [operatorSnap, treeSnap] = await Promise.all([
        transaction.get(operatorRef),
        transaction.get(treeRef),
      ]);

      const operator = requireOperator(operatorSnap);
      if (!treeSnap.exists) throw notFound();

      const tree = treeSnap.data();
      if (tree.rtId !== operator.rtId) throw deny();

      if (tree.status === 'VERIFIED' || tree.status === 'REJECTED') {
        if (tree.verificationCommandHash === commandHash) {
          return {
            treePointId,
            status: tree.status,
            verifiedAt: iso(tree.verifiedAt),
          };
        }
        throw fail('failed-precondition', 'Titik pohon sudah diproses sebelumnya.');
      }

      if (tree.status !== 'PENDING_RT_VERIFICATION') {
        throw fail('failed-precondition', 'Status titik pohon tidak valid untuk verifikasi.');
      }

      const newStatus = decision === 'APPROVE' ? 'VERIFIED' : 'REJECTED';

      transaction.update(treeRef, {
        status: newStatus,
        rejectionReason: decision === 'REJECT' ? rejectionReason : null,
        verifiedByOperatorUid: operatorUid,
        verifiedAt: now,
        verificationCommandHash: commandHash,
        updatedAt: now,
      });

      transaction.create(auditRef, {
        auditId: `${treePointId}_${decision.toLowerCase()}`,
        action: decision === 'APPROVE' ? 'TREE_POINT_VERIFIED' : 'TREE_POINT_REJECTED',
        treePointId,
        rtId: operator.rtId,
        actorUid: operatorUid,
        decision,
        rejectionReason: decision === 'REJECT' ? rejectionReason : null,
        commandHash,
        occurredAt: now,
      });

      return {
        treePointId,
        status: newStatus,
        verifiedAt: iso(now),
      };
    });
  }

  async deleteTreePoint({ actorUid, isOperator, rtId, treePointId, reason, now }) {
    const treeRef = this.firestore.collection(TREE_POINT_COLLECTION).doc(treePointId);
    const privateLocationRef = treeRef.collection('private').doc('location');

    return this.firestore.runTransaction(async (transaction) => {
      const treeSnap = await transaction.get(treeRef);
      if (!treeSnap.exists) throw notFound();

      const tree = treeSnap.data();

      if (isOperator) {
        const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(actorUid);
        const operatorSnap = await transaction.get(operatorRef);
        const operator = requireOperator(operatorSnap);
        if (tree.rtId !== operator.rtId) throw deny();
      } else {
        if (tree.residentId !== actorUid || tree.rtId !== rtId) throw deny();
        if (tree.status !== 'PENDING_RT_VERIFICATION') {
          throw fail('failed-precondition', 'Hanya titik pohon yang belum diverifikasi yang dapat dibatalkan warga.');
        }
      }

      transaction.delete(privateLocationRef);
      transaction.delete(treeRef);

      return {
        deleted: true,
        treePointId,
      };
    });
  }

  async anonymizeResidentTreePoints({ rtId, residentId, now }) {
    const snapshot = await this.firestore.collection(TREE_POINT_COLLECTION)
      .where('rtId', '==', rtId)
      .where('residentId', '==', residentId)
      .get();

    if (snapshot.empty) return;

    const batch = this.firestore.batch();
    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        isAnonymous: true,
        submitterNickname: 'Pohon Warga (Anonim)',
        evidenceId: null,
        updatedAt: now,
      });
      const privateLocationRef = doc.ref.collection('private').doc('location');
      batch.delete(privateLocationRef);
    }
    await batch.commit();
  }
}

module.exports = {
  FirestoreTreePointRepository,
  TREE_POINT_COLLECTION,
};
