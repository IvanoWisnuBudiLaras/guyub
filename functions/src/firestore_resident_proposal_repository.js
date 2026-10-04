const {
  OPERATOR_ROLES,
  asDate,
} = require('./task_campaign_service');
const { ResidentProposalError, MAX_PENDING_PROPOSALS } = require('./resident_proposal_service');

const PROPOSAL_COLLECTION = 'resident_proposals';
const SESSION_COLLECTION = 'resident_sessions';
const RESIDENT_COLLECTION = 'resident_profiles';
const OPERATOR_COLLECTION = 'operators';
const AUDIT_COLLECTION = 'resident_proposal_audit_events';

function fail(code, message = 'Akses usulan tidak valid.') {
  return new ResidentProposalError(code, message);
}

function deny() {
  return fail('permission-denied');
}

function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true || !OPERATOR_ROLES.has(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) {
    throw deny();
  }
  return { rtId: data.rtId.trim(), role: data.role };
}

function requireResidentSession(sessionSnapshot, residentSnapshot, input) {
  const session = sessionSnapshot.data();
  const resident = residentSnapshot.data();
  const expiresAt = asDate(session?.expiresAt);
  if (!sessionSnapshot.exists || session?.active !== true || !expiresAt ||
      expiresAt <= input.now || session.residentId !== input.residentId ||
      session.rtId !== input.rtId || !residentSnapshot.exists ||
      resident?.rtId !== input.rtId || typeof resident?.nickname !== 'string') {
    throw deny();
  }
}

function proposalFromSnapshot(snapshot) {
  if (!snapshot.exists) return null;
  const proposal = snapshot.data();
  if (proposal?.proposalId !== snapshot.id || typeof proposal.rtId !== 'string' ||
      typeof proposal.residentId !== 'string' || typeof proposal.title !== 'string' ||
      typeof proposal.description !== 'string' || typeof proposal.category !== 'string' ||
      !['SUBMITTED', 'DISMISSED'].includes(proposal.state) || !asDate(proposal.submittedAt)) {
    return null;
  }
  return {
    proposalId: proposal.proposalId,
    rtId: proposal.rtId,
    residentId: proposal.residentId,
    title: proposal.title,
    description: proposal.description,
    category: proposal.category,
    locationReference: proposal.locationReference ?? null,
    state: proposal.state,
    submittedAt: proposal.submittedAt,
    ...(proposal.reviewedAt == null ? {} : { reviewedAt: proposal.reviewedAt }),
  };
}

function publicQueueItem(proposal, nickname) {
  return { ...proposal, nickname };
}

function auditMatches(audit, input, operator) {
  return audit?.action === 'RESIDENT_PROPOSAL_DISMISSED' &&
    audit.proposalId === input.proposalId && audit.rtId === operator.rtId &&
    audit.actorUid === input.operatorUid && audit.commandHash === input.commandHash;
}

class FirestoreResidentProposalRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async submitProposal(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(RESIDENT_COLLECTION).doc(input.residentId);
    const proposalRef = this.firestore.collection(PROPOSAL_COLLECTION).doc(input.proposalId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, proposalSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(proposalRef),
      ]);
      requireResidentSession(sessionSnapshot, residentSnapshot, input);
      if (proposalSnapshot.exists) {
        const existing = proposalSnapshot.data();
        if (existing.proposalId !== input.proposalId || existing.rtId !== input.rtId ||
            existing.residentId !== input.residentId ||
            existing.requestFingerprint !== input.requestFingerprint) {
          throw fail('already-exists', 'ID permintaan sudah digunakan.');
        }
        result = existing;
        return;
      }

      result = {
        proposalId: input.proposalId,
        rtId: input.rtId,
        residentId: input.residentId,
        title: input.title,
        description: input.description,
        category: input.category,
        locationReference: input.locationReference,
        state: 'SUBMITTED',
        submittedAt: input.now,
        requestFingerprint: input.requestFingerprint,
      };
      transaction.create(proposalRef, result);
    });
    return result;
  }

  async listProposals({ operatorUid }) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(operatorUid);
    return this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      const query = this.firestore.collection(PROPOSAL_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('state', '==', 'SUBMITTED')
        .orderBy('submittedAt', 'asc')
        .limit(MAX_PENDING_PROPOSALS + 1);
      const proposalsSnapshot = await transaction.get(query);
      const docs = proposalsSnapshot.docs.slice(0, MAX_PENDING_PROPOSALS);
      const residents = await Promise.all(docs.map((proposalSnapshot) => {
        const proposal = proposalSnapshot.data();
        return transaction.get(this.firestore.collection(RESIDENT_COLLECTION).doc(proposal.residentId));
      }));
      const items = docs.map((proposalSnapshot, index) => {
        const proposal = proposalFromSnapshot(proposalSnapshot);
        const residentSnapshot = residents[index];
        if (!proposal || proposal.rtId !== operator.rtId || proposal.state !== 'SUBMITTED' ||
            !residentSnapshot.exists || residentSnapshot.data().rtId !== operator.rtId ||
            typeof residentSnapshot.data().nickname !== 'string') return null;
        return publicQueueItem(proposal, residentSnapshot.data().nickname);
      }).filter((proposal) => proposal !== null).sort((left, right) => {
        return (asDate(left.submittedAt)?.getTime() ?? 0) -
          (asDate(right.submittedAt)?.getTime() ?? 0);
      });
      return { items, isPartial: proposalsSnapshot.size > MAX_PENDING_PROPOSALS };
    });
  }

  async reviewProposal(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const proposalRef = this.firestore.collection(PROPOSAL_COLLECTION).doc(input.proposalId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION)
      .doc(`${input.proposalId}_dismissed`);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, proposalSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(proposalRef), transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      const proposal = proposalFromSnapshot(proposalSnapshot);
      if (!proposal) throw deny();
      if (proposal.rtId !== operator.rtId) throw deny();

      if (proposal.state === 'DISMISSED') {
        const storedProposal = proposalSnapshot.data();
        if (storedProposal.reviewDecision === 'DISMISSED' &&
            storedProposal.reviewCommandHash === input.commandHash &&
            storedProposal.reviewedByOperatorUid === input.operatorUid && auditSnapshot.exists &&
            auditMatches(auditSnapshot.data(), input, operator)) {
          result = storedProposal;
          return;
        }
        throw fail('failed-precondition', 'Usulan sudah ditinjau.');
      }
      if (proposal.state !== 'SUBMITTED') {
        throw fail('failed-precondition', 'Usulan tidak menunggu peninjauan.');
      }
      if (auditSnapshot.exists) throw fail('failed-precondition', 'Riwayat peninjauan tidak konsisten.');

      const update = {
        state: 'DISMISSED',
        reviewDecision: 'DISMISSED',
        reviewCommandHash: input.commandHash,
        reviewedByOperatorUid: input.operatorUid,
        reviewedAt: input.now,
      };
      transaction.update(proposalRef, update);
      transaction.create(auditRef, {
        auditId: `${input.proposalId}_dismissed`,
        proposalId: input.proposalId,
        rtId: operator.rtId,
        action: 'RESIDENT_PROPOSAL_DISMISSED',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        occurredAt: input.now,
      });
      result = { ...proposalSnapshot.data(), ...update };
    });
    return result;
  }
}

module.exports = { FirestoreResidentProposalRepository };
