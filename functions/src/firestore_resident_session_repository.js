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
        transaction.create(sessionRef, replacementSession);
        if (previousSessionSnapshot.exists && previousSessionSnapshot.data().active === true) {
          transaction.update(previousSessionRef, {
            active: false,
            revokedAt: record.session.createdAt,
          });
        }
        transaction.update(enrollmentRef, {
          sessionHash: record.sessionId,
          updatedAt: record.session.createdAt,
        });
        committedResidentId = enrollment.residentId;
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
    return { residentId: committedResidentId };
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
