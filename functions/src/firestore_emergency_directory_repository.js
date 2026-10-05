const { EmergencyDirectoryError } = require('./emergency_directory_service');

const SESSION_COLLECTION = 'resident_sessions';
const RESIDENT_COLLECTION = 'resident_profiles';
const COMMUNITY_COLLECTION = 'rt_communities';
const DIRECTORY_COLLECTION = 'emergency_directories';

function deny() {
  return new EmergencyDirectoryError('permission-denied', 'Akses direktori darurat tidak valid.');
}

function asDate(value) {
  let date;
  if (value instanceof Date) date = value;
  else if (value && typeof value.toDate === 'function') {
    try {
      date = value.toDate();
    } catch (_) {
      return null;
    }
  } else {
    return null;
  }
  return date instanceof Date && Number.isFinite(date.getTime()) ? date : null;
}

function requireResidentSession(sessionSnapshot, residentSnapshot, communitySnapshot, input) {
  const session = sessionSnapshot.data();
  const resident = residentSnapshot.data();
  const expiresAt = asDate(session?.expiresAt);
  if (!sessionSnapshot.exists || session?.active !== true || !expiresAt ||
      expiresAt <= input.now || session.residentId !== input.residentId ||
      session.rtId !== input.rtId || !residentSnapshot.exists ||
      resident?.rtId !== input.rtId || resident?.deletionPending === true ||
      typeof resident?.nickname !== 'string' ||
      !resident.nickname.trim() || !communitySnapshot.exists ||
      communitySnapshot.id !== input.rtId) {
    throw deny();
  }
}

class FirestoreEmergencyDirectoryRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async getDirectoryForResident(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const communityRef = this.firestore.collection(COMMUNITY_COLLECTION).doc(input.rtId);
    const directoryRef = this.firestore.collection(DIRECTORY_COLLECTION).doc(input.rtId);

    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, communitySnapshot, directorySnapshot] =
        await Promise.all([
          transaction.get(sessionRef),
          transaction.get(residentRef),
          transaction.get(communityRef),
          transaction.get(directoryRef),
        ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, communitySnapshot, input);
      return directorySnapshot.exists ? directorySnapshot.data() : null;
    });
  }
}

module.exports = { FirestoreEmergencyDirectoryRepository };
