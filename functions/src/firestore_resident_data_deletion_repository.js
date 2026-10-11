const crypto = require('node:crypto');
const { OPERATOR_ROLES } = require('./task_campaign_service');
const { ProxyResidentError } = require('./proxy_resident_service');
const { residentScopeHash } = require('./task_evidence_service');
const { residentProfileTombstoneId } = require('./resident_profile_tombstone');
const { hasActiveUploadLease } = require('./task_evidence_upload_lease');

const PAGE_SIZE = 400;
const JOB_COLLECTION = 'resident_data_deletion_jobs';
const AUDIT_COLLECTION = 'resident_data_deletion_audit_events';

function fail(code, message = 'Data warga belum dapat dihapus. Coba lagi.') {
  return new ProxyResidentError(code, message);
}
function deny() {
  throw fail('permission-denied', 'Akses penghapusan data tidak valid.');
}
function targetHash(rtId, residentId) {
  return crypto.createHash('sha256')
    .update(`resident-deletion\0${rtId}\0${residentId}`, 'utf8')
    .digest('hex');
}
function requireOperator(snapshot) {
  const operator = snapshot.data();
  if (!snapshot.exists || operator?.active !== true || !OPERATOR_ROLES.has(operator.role) ||
      typeof operator.rtId !== 'string' || !operator.rtId.trim()) deny();
  return { rtId: operator.rtId.trim(), role: operator.role };
}

class FirestoreResidentDataDeletionRepository {
  constructor(firestore, storage) {
    this.firestore = firestore;
    this.storage = storage;
  }

  async deleteResidentData(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    let rtId;
    let completed = false;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, residentSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(residentRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      rtId = operator.rtId;
      const scopedHash = targetHash(rtId, input.residentId);
      const scopedJobRef = this.firestore.collection(JOB_COLLECTION).doc(scopedHash);
      const scopedAuditRef = this.firestore.collection(AUDIT_COLLECTION).doc(scopedHash);
      const [scopedJobSnapshot, scopedAuditSnapshot] = await Promise.all([
        transaction.get(scopedJobRef), transaction.get(scopedAuditRef),
      ]);
      if (scopedAuditSnapshot.exists) {
        const audit = scopedAuditSnapshot.data();
        if (audit.rtId !== operator.rtId || audit.targetResidentHash !== scopedHash ||
            audit.action !== 'RESIDENT_DATA_DELETED') deny();
        completed = true;
        return;
      }
      if (scopedJobSnapshot.exists) {
        const job = scopedJobSnapshot.data();
        if (job.rtId !== operator.rtId || job.targetResidentHash !== scopedHash ||
            job.residentId !== input.residentId) deny();
        return;
      }
      if (!residentSnapshot.exists || residentSnapshot.id !== input.residentId ||
          residentSnapshot.data()?.rtId !== operator.rtId) deny();
      if (residentSnapshot.data()?.deletionPending === true) {
        throw fail('failed-precondition', 'Penghapusan data warga sedang diproses.');
      }
      transaction.create(scopedJobRef, {
        targetResidentHash: scopedHash,
        residentId: input.residentId,
        rtId: operator.rtId,
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        residentRequestConfirmed: input.residentRequestConfirmed,
        identityVerificationConfirmed: input.identityVerificationConfirmed,
        createdAt: input.now,
      });
      transaction.update(residentRef, {
        deletionPending: true,
        deletionRequestedAt: input.now,
      });
    });

    if (completed) return { deleted: true };
    if (!rtId) throw fail('permission-denied', 'Akses penghapusan data tidak valid.');
    const scopedHash = targetHash(rtId, input.residentId);
    const scopedJobRef = this.firestore.collection(JOB_COLLECTION).doc(scopedHash);
    const scopedAuditRef = this.firestore.collection(AUDIT_COLLECTION).doc(scopedHash);
    const jobSnapshot = await scopedJobRef.get();
    if (!jobSnapshot.exists) {
      const auditSnapshot = await scopedAuditRef.get();
      if (auditSnapshot.exists && auditSnapshot.data()?.rtId === rtId) return { deleted: true };
      throw fail('failed-precondition', 'Penghapusan data tidak dapat dilanjutkan.');
    }

    await this._deleteEvidence(input, rtId);
    await this._tombstoneEnrollments(input.residentId, rtId, input.now);
    const residentCollections = [
      ['resident_sessions', 'residentId', input.residentId],
      ['task_responses', 'residentId', input.residentId],
      ['resident_proposals', 'residentId', input.residentId],
      ['proxy_status_audit_events', 'targetResidentId', input.residentId],
      ['resident_push_tokens', 'residentId', input.residentId],
      ['assistance_assignments', 'residentNeedingHelpId', input.residentId],
      ['assistance_assignments', 'helperResidentId', input.residentId],
      ['assistance_assignment_pair_guards', 'residentNeedingHelpId', input.residentId],
      ['assistance_assignment_pair_guards', 'helperResidentId', input.residentId],
      ['assistance_assignment_audit_events', 'targetResidentHash',
        crypto.createHash('sha256').update(`resident-assistance\0${rtId}\0${input.residentId}`).digest('hex')],
      ['assistance_assignment_audit_events', 'helperResidentHash',
        crypto.createHash('sha256').update(`resident-assistance\0${rtId}\0${input.residentId}`).digest('hex')],
      ['assistance_assignment_audit_events', 'actorResidentHash',
        crypto.createHash('sha256').update(`resident-assistance\0${rtId}\0${input.residentId}`).digest('hex')],
    ];
    for (const [collectionName, field, value] of residentCollections) {
      await this._deleteByField(collectionName, field, value);
    }

    await this.firestore.runTransaction(async (transaction) => {
      const tombstoneId = residentProfileTombstoneId(rtId, input.residentId);
      const tombstoneRef = this.firestore.collection('resident_profile_tombstones').doc(tombstoneId);
      const [operatorSnapshot, residentSnapshot, currentJob, currentAudit, currentTombstone] =
        await Promise.all([
          transaction.get(operatorRef), transaction.get(residentRef),
          transaction.get(scopedJobRef), transaction.get(scopedAuditRef),
          transaction.get(tombstoneRef),
        ]);
      const operator = requireOperator(operatorSnapshot);
      if (operator.rtId !== rtId) deny();
      if (currentAudit.exists) {
        const audit = currentAudit.data();
        if (audit.action !== 'RESIDENT_DATA_DELETED' || audit.rtId !== rtId ||
            audit.targetResidentHash !== scopedHash) deny();
        return;
      }
      if (!currentJob.exists || currentJob.data()?.targetResidentHash !== scopedHash ||
          currentJob.data()?.residentId !== input.residentId || currentJob.data()?.rtId !== rtId) {
        throw fail('failed-precondition', 'Riwayat penghapusan tidak konsisten.');
      }
      if (residentSnapshot.exists) {
        const resident = residentSnapshot.data();
        if (resident.rtId !== rtId || resident.deletionPending !== true) deny();
        transaction.delete(residentRef);
      }
      const job = currentJob.data();
      if (currentTombstone.exists &&
          (currentTombstone.data()?.rtId !== rtId ||
           currentTombstone.data()?.targetResidentHash !== tombstoneId)) deny();
      transaction.set(tombstoneRef, {
        tombstoneId,
        rtId,
        targetResidentHash: tombstoneId,
        action: 'RESIDENT_DATA_DELETED',
        occurredAt: input.now,
      });
      transaction.create(scopedAuditRef, {
        auditId: scopedHash,
        action: 'RESIDENT_DATA_DELETED',
        rtId,
        targetResidentHash: scopedHash,
        actorUid: job.actorUid,
        commandHash: job.commandHash,
        residentRequestConfirmed: job.residentRequestConfirmed === true,
        identityVerificationConfirmed: job.identityVerificationConfirmed === true,
        occurredAt: input.now,
      });
      transaction.delete(scopedJobRef);
    });
    return { deleted: true };
  }

  async _deleteEvidence(input, rtId) {
    const scopeHash = residentScopeHash(rtId, input.residentId);
    const residentHash = crypto.createHash('sha256').update(input.residentId, 'utf8').digest('hex');
    const communityHash = crypto.createHash('sha256').update(rtId, 'utf8').digest('hex');
    const expectedPrefix = `evidence/${communityHash.slice(0, 20)}/${residentHash.slice(0, 40)}/`;
    const collection = this.firestore.collection('task_evidence');
    while (true) {
      const snapshot = await collection.where('residentScopeHash', '==', scopeHash)
        .limit(PAGE_SIZE).get();
      if (snapshot.empty) return;
      for (const document of snapshot.docs) {
        const record = document.data();
        if (record.status === 'DELETED') continue;
        if (hasActiveUploadLease(record, input.now)) {
          throw fail('failed-precondition', 'Unggahan bukti warga masih berlangsung. Coba lagi.');
        }
        if (!['READY', 'DELETE_PENDING', 'UPLOADING'].includes(record.status) ||
            typeof record.storagePath !== 'string' || record.storagePath.length === 0) {
          throw fail('failed-precondition', 'Lokasi bukti warga tidak valid.');
        }
        const storagePath = record.storagePath;
        const filename = storagePath.slice(expectedPrefix.length);
        if (!storagePath.startsWith(expectedPrefix) || !/^[a-f0-9]{40}\.jpg$/u.test(filename)) {
          throw fail('failed-precondition', 'Lokasi bukti warga tidak valid.');
        }
        if (!this.storage || typeof this.storage.delete !== 'function') {
          throw fail('failed-precondition', 'Penyimpanan bukti belum dikonfigurasi.');
        }
        try {
          await this.storage.delete(storagePath);
        } catch (_) {
          throw fail('unavailable', 'Bukti warga belum dapat dihapus. Coba lagi.');
        }
      }
      const batch = this.firestore.batch();
      for (const document of snapshot.docs) batch.delete(document.ref);
      await batch.commit();
    }
  }

  async _tombstoneEnrollments(residentId, rtId, now) {
    const collection = this.firestore.collection('resident_enrollments');
    while (true) {
      const snapshot = await collection.where('residentId', '==', residentId)
        .limit(PAGE_SIZE).get();
      if (snapshot.empty) return;
      const batch = this.firestore.batch();
      for (const document of snapshot.docs) {
        const enrollment = document.data();
        if (enrollment.residentId !== residentId || enrollment.rtId !== rtId) deny();
        batch.set(document.ref, { rtId, status: 'DELETED', deletedAt: now });
      }
      await batch.commit();
    }
  }

  async _deleteByField(collectionName, field, value) {
    const collection = this.firestore.collection(collectionName);
    while (true) {
      const snapshot = await collection.where(field, '==', value).limit(PAGE_SIZE).get();
      if (snapshot.empty) return;
      const batch = this.firestore.batch();
      for (const document of snapshot.docs) batch.delete(document.ref);
      await batch.commit();
    }
  }
}

module.exports = { FirestoreResidentDataDeletionRepository };
