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
    return this._deleteResidentData(input, 'RT_OPERATOR');
  }

  async deleteOwnResidentData(input) {
    return this._deleteResidentData(input, 'RESIDENT_SELF');
  }

  async _deleteResidentData(input, actorKind) {
    const isResidentSelf = actorKind === 'RESIDENT_SELF';
    const operatorRef = isResidentSelf ? null :
      this.firestore.collection('operators').doc(input.operatorUid);
    const sessionRef = isResidentSelf ?
      this.firestore.collection('resident_sessions').doc(input.actorSessionHash) : null;
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    const rtId = isResidentSelf ? input.rtId : null;
    let resolvedRtId = rtId;
    let completed = false;

    await this.firestore.runTransaction(async (transaction) => {
      const actorPromise = operatorRef ? transaction.get(operatorRef) :
        transaction.get(sessionRef);
      const [actorSnapshot, residentSnapshot] = await Promise.all([
        actorPromise,
        transaction.get(residentRef),
      ]);
      if (!isResidentSelf) {
        resolvedRtId = requireOperator(actorSnapshot).rtId;
      }
      if (typeof resolvedRtId !== 'string' || !resolvedRtId.trim()) deny();

      const scopedHash = targetHash(resolvedRtId, input.residentId);
      const scopedJobRef = this.firestore.collection(JOB_COLLECTION).doc(scopedHash);
      const scopedAuditRef = this.firestore.collection(AUDIT_COLLECTION).doc(scopedHash);
      const [scopedJobSnapshot, scopedAuditSnapshot] = await Promise.all([
        transaction.get(scopedJobRef),
        transaction.get(scopedAuditRef),
      ]);
      if (scopedAuditSnapshot.exists) {
        const audit = scopedAuditSnapshot.data();
        if (audit.rtId !== resolvedRtId || audit.targetResidentHash !== scopedHash ||
            audit.action !== 'RESIDENT_DATA_DELETED') deny();
        if (isResidentSelf &&
            (audit.actorKind !== 'RESIDENT_SELF' ||
             audit.commandHash !== input.commandHash)) deny();
        completed = true;
        return;
      }
      if (scopedJobSnapshot.exists) {
        const job = scopedJobSnapshot.data();
        const jobActorKind = job.actorKind ?? 'RT_OPERATOR';
        if (job.rtId !== resolvedRtId || job.targetResidentHash !== scopedHash ||
            job.residentId !== input.residentId ||
            (isResidentSelf &&
             (jobActorKind !== 'RESIDENT_SELF' ||
              job.actorSessionHash !== input.actorSessionHash ||
              job.commandHash !== input.commandHash))) {
          deny();
        }
      } else {
        if (isResidentSelf) {
          const session = actorSnapshot.data();
          const expiresAt = session?.expiresAt?.toDate?.() ?? session?.expiresAt;
          const expiry = expiresAt instanceof Date ? expiresAt : new Date(expiresAt);
          if (!actorSnapshot.exists || session?.active !== true ||
              !Number.isFinite(expiry.getTime()) || expiry <= input.now ||
              session.residentId !== input.residentId || session.rtId !== resolvedRtId) {
            deny();
          }
        }
        if (!residentSnapshot.exists || residentSnapshot.data()?.rtId !== resolvedRtId ||
            residentSnapshot.data()?.deletionPending === true) {
          deny();
        }
        const job = {
          targetResidentHash: scopedHash,
          residentId: input.residentId,
          rtId: resolvedRtId,
          actorKind,
          commandHash: input.commandHash,
          residentRequestConfirmed: input.residentRequestConfirmed === true,
          identityVerificationConfirmed: input.identityVerificationConfirmed === true,
          createdAt: input.now,
        };
        if (operatorRef) job.actorUid = input.operatorUid;
        if (isResidentSelf) job.actorSessionHash = input.actorSessionHash;
        transaction.create(scopedJobRef, job);
        transaction.update(residentRef, {
          deletionPending: true,
          deletionRequestedAt: input.now,
        });
      }
    });

    if (completed) return { deleted: true };
    if (!resolvedRtId) throw fail('permission-denied', 'Akses penghapusan data tidak valid.');
    const scopedHash = targetHash(resolvedRtId, input.residentId);
    const scopedJobRef = this.firestore.collection(JOB_COLLECTION).doc(scopedHash);
    const scopedAuditRef = this.firestore.collection(AUDIT_COLLECTION).doc(scopedHash);
    const jobSnapshot = await scopedJobRef.get();
    if (!jobSnapshot.exists) {
      const auditSnapshot = await scopedAuditRef.get();
      if (auditSnapshot.exists && auditSnapshot.data()?.rtId === resolvedRtId) {
        return { deleted: true };
      }
      throw fail('failed-precondition', 'Penghapusan data tidak dapat dilanjutkan.');
    }

    await this._finishDeletion({
      input,
      rtId: resolvedRtId,
      scopedHash,
      scopedJobRef,
      scopedAuditRef,
      operatorRef,
    });
    return { deleted: true };
  }

  async _finishDeletion({
    input,
    rtId,
    scopedHash,
    scopedJobRef,
    scopedAuditRef,
    operatorRef,
  }) {
    const residentRef = this.firestore.collection('resident_profiles').doc(input.residentId);
    await this._deleteEvidence(input, rtId);
    await this._tombstoneEnrollments(input.residentId, rtId, input.now);
    const assistanceHash = crypto.createHash('sha256')
      .update(`resident-assistance\0${rtId}\0${input.residentId}`, 'utf8').digest('hex');
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
      ['assistance_assignment_audit_events', 'targetResidentHash', assistanceHash],
      ['assistance_assignment_audit_events', 'helperResidentHash', assistanceHash],
      ['assistance_assignment_audit_events', 'actorResidentHash', assistanceHash],
    ];
    for (const [collectionName, field, value] of residentCollections) {
      await this._deleteByField(collectionName, field, value);
    }

    await this.firestore.runTransaction(async (transaction) => {
      const tombstoneId = residentProfileTombstoneId(rtId, input.residentId);
      const tombstoneRef = this.firestore.collection('resident_profile_tombstones').doc(tombstoneId);
      const reads = [
        transaction.get(residentRef),
        transaction.get(scopedJobRef),
        transaction.get(scopedAuditRef),
        transaction.get(tombstoneRef),
      ];
      if (operatorRef) reads.push(transaction.get(operatorRef));
      const [residentSnapshot, currentJob, currentAudit, currentTombstone, operatorSnapshot] =
        await Promise.all(reads);
      if (operatorRef) {
        const operator = requireOperator(operatorSnapshot);
        if (operator.rtId !== rtId) deny();
      }
      if (currentAudit.exists) {
        const audit = currentAudit.data();
        if (audit.action !== 'RESIDENT_DATA_DELETED' || audit.rtId !== rtId ||
            audit.targetResidentHash !== scopedHash) deny();
        return;
      }
      if (!currentJob.exists || currentJob.data()?.targetResidentHash !== scopedHash ||
          currentJob.data()?.residentId !== input.residentId ||
          currentJob.data()?.rtId !== rtId) {
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
      const audit = {
        auditId: scopedHash,
        action: 'RESIDENT_DATA_DELETED',
        actorKind: job.actorKind ?? 'RT_OPERATOR',
        rtId,
        targetResidentHash: scopedHash,
        commandHash: job.commandHash,
        residentRequestConfirmed: job.residentRequestConfirmed === true,
        identityVerificationConfirmed: job.identityVerificationConfirmed === true,
        occurredAt: input.now,
      };
      if (typeof job.actorUid === 'string') audit.actorUid = job.actorUid;
      transaction.create(scopedAuditRef, audit);
      transaction.delete(scopedJobRef);
    });
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
