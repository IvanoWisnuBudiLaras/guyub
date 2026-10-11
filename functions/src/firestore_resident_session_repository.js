const { FieldValue } = require('firebase-admin/firestore');
const { SessionServiceError } = require('./resident_session_service');

class FirestoreResidentSessionRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async findCommunityByJoinCodeHash(joinCodeHash) {
    const snapshot = await this.firestore
      .collection('rt_communities')
      .where('joinCodeHash', '==', joinCodeHash)
      .limit(2)
      .get();
    if (snapshot.size !== 1) return null;
    const community = communityFrom(snapshot.docs[0]);
    return community.joinCodeActive ? community : null;
  }

  async createResidentAndSession(record) {
    const communityRef = this.firestore.collection('rt_communities').doc(record.communityId);
    const enrollmentRef = this.firestore.collection('resident_enrollments').doc(record.requestHash);
    const candidateResidentRef = this.firestore
      .collection('resident_profiles')
      .doc(record.residentId);
    const sessionRef = this.firestore.collection('resident_sessions').doc(record.sessionId);
    let committedResidentId;
    let sessionsToCleanup = [];

    await this.firestore.runTransaction(async (transaction) => {
      const communitySnapshot = await transaction.get(communityRef);
      const enrollmentSnapshot = await transaction.get(enrollmentRef);
      const sessionSnapshot = await transaction.get(sessionRef);
      const community = communitySnapshot.data();
      if (!communitySnapshot.exists ||
          community.joinCodeActive !== true ||
          community.joinCodeHash !== record.expectedJoinCodeHash) {
        throw new SessionServiceError(
          'permission-denied',
          'Kode RT tidak valid atau tidak aktif.',
        );
      }
      if (sessionSnapshot.exists) {
        throw new SessionServiceError('aborted', 'Sesi tidak dapat dibuat. Coba lagi.');
      }

      if (enrollmentSnapshot.exists) {
        const enrollment = enrollmentSnapshot.data();
        if (enrollment.status === 'DELETED') {
          throw new SessionServiceError(
            'permission-denied',
            'Kode RT tidak valid atau tidak aktif.',
          );
        }
        if (enrollment.rtId !== record.communityId ||
            enrollment.requestFingerprint !== record.requestFingerprint ||
            typeof enrollment.residentId !== 'string' ||
            typeof enrollment.sessionHash !== 'string') {
          throw new SessionServiceError(
            'permission-denied',
            'Permintaan pendaftaran tidak valid.',
          );
        }
        const residentRef = this.firestore
          .collection('resident_profiles')
          .doc(enrollment.residentId);
        const previousSessionRef = this.firestore
          .collection('resident_sessions')
          .doc(enrollment.sessionHash);
        const residentSnapshot = await transaction.get(residentRef);
        const previousSessionSnapshot = await transaction.get(previousSessionRef);
        if (!residentSnapshot.exists || residentSnapshot.data().rtId !== record.communityId ||
            residentSnapshot.data().deletionPending === true) {
          throw new SessionServiceError(
            'permission-denied',
            'Permintaan pendaftaran tidak valid.',
          );
        }

        const replacementSession = {
          ...record.session,
          residentId: enrollment.residentId,
        };
        // [rotasi-sesi:retensi-token-fcm]: Catat sesi lama ke pendingTokenCleanups agar retry tetap membersihkan token orphan.
        const pendingCleanups = [
          ...(Array.isArray(enrollment.pendingTokenCleanups) ? enrollment.pendingTokenCleanups : []),
          ...(enrollment.sessionHash ? [enrollment.sessionHash] : []),
        ].filter((hash) => typeof hash === 'string' && hash !== record.sessionId);
        const uniquePending = [...new Set(pendingCleanups)];

        transaction.create(sessionRef, replacementSession);
        if (previousSessionSnapshot.exists && previousSessionSnapshot.data().active === true) {
          transaction.update(previousSessionRef, {
            active: false,
            revokedAt: record.session.createdAt,
          });
        }
        transaction.update(enrollmentRef, {
          sessionHash: record.sessionId,
          pendingTokenCleanups: uniquePending,
          updatedAt: record.session.createdAt,
        });
        committedResidentId = enrollment.residentId;
        sessionsToCleanup = uniquePending;
        return;
      }

      transaction.create(candidateResidentRef, record.resident);
      transaction.create(sessionRef, record.session);
      transaction.create(enrollmentRef, {
        rtId: record.communityId,
        requestFingerprint: record.requestFingerprint,
        residentId: record.residentId,
        sessionHash: record.sessionId,
        createdAt: record.session.createdAt,
        updatedAt: record.session.createdAt,
      });
      committedResidentId = record.residentId;
    });

    for (const oldSessionId of sessionsToCleanup) {
      await this._deletePushTokensForSession(oldSessionId);
      await this._removePendingTokenCleanup(enrollmentRef, oldSessionId);
    }
    return { residentId: committedResidentId };
  }

  async _removePendingTokenCleanup(enrollmentRef, sessionId) {
    try {
      await this.firestore.runTransaction(async (transaction) => {
        const snap = await transaction.get(enrollmentRef);
        if (!snap.exists) return;
        const current = snap.data()?.pendingTokenCleanups;
        if (!Array.isArray(current) || !current.includes(sessionId)) return;
        const remaining = current.filter((id) => id !== sessionId);
        if (remaining.length > 0) {
          transaction.update(enrollmentRef, { pendingTokenCleanups: remaining });
        } else {
          transaction.update(enrollmentRef, {
            pendingTokenCleanups: FieldValue.delete(),
          });
        }
      });
    } catch (_) {
      // Non-fatal: token is deleted; next run will safely no-op delete
    }
  }

  async getSession(sessionId) {
    const snapshot = await this.firestore.collection('resident_sessions').doc(sessionId).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  async getResident(residentId) {
    const snapshot = await this.firestore.collection('resident_profiles').doc(residentId).get();
    return snapshot.exists ? snapshot.data() : null;
  }

  async getCommunity(communityId) {
    const snapshot = await this.firestore.collection('rt_communities').doc(communityId).get();
    return snapshot.exists ? communityFrom(snapshot) : null;
  }

  async revokeSession(sessionId, revokedAt) {
    const sessionRef = this.firestore.collection('resident_sessions').doc(sessionId);
    await this.firestore.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(sessionRef);
      if (!snapshot.exists || snapshot.data().active !== true) return;
      transaction.update(sessionRef, { active: false, revokedAt });
    });
    await this._deletePushTokensForSession(sessionId);
  }

  async _deletePushTokensForSession(sessionId) {
    const tokenCollection = this.firestore.collection('resident_push_tokens');
    while (true) {
      const tokens = await tokenCollection.where('sessionIdHash', '==', sessionId).limit(400).get();
      if (tokens.empty) return;
      const batch = this.firestore.batch();
      for (const token of tokens.docs) batch.delete(token.ref);
      await batch.commit();
    }
  }
}

function communityFrom(snapshot) {
  const data = snapshot.data();
  return {
    id: snapshot.id,
    displayName: typeof data.displayName === 'string' ? data.displayName : '',
    rtLabel: typeof data.rtLabel === 'string' ? data.rtLabel : '',
    joinCodeHash: typeof data.joinCodeHash === 'string' ? data.joinCodeHash : '',
    joinCodeActive: data.joinCodeActive === true,
  };
}

module.exports = { FirestoreResidentSessionRepository };
