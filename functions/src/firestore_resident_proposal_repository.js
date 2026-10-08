const crypto = require('node:crypto');
const {
  OPERATOR_ROLES,
  TASK_CATEGORIES,
  TASK_LOCATION_REFERENCES,
  asDate,
  approvedTemplateFromRecord,
  publicTemplate,
  templateDocumentId,
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
      resident?.rtId !== input.rtId || resident?.deletionPending === true ||
      typeof resident?.nickname !== 'string') {
    throw deny();
  }
}

function proposalFromSnapshot(snapshot) {
  if (!snapshot.exists) return null;
  const proposal = snapshot.data();
  if (proposal?.proposalId !== snapshot.id || typeof proposal.rtId !== 'string' ||
      typeof proposal.residentId !== 'string' || typeof proposal.title !== 'string' ||
      typeof proposal.description !== 'string' || typeof proposal.category !== 'string' ||
      !['SUBMITTED', 'DISMISSED', 'NEEDS_OFFICIAL_REPORT', 'MAPPED_TO_SAFE_TEMPLATE'].includes(proposal.state) ||
      !asDate(proposal.submittedAt)) {
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
  const expectedAction = input.decision === 'NEEDS_OFFICIAL_REPORT'
    ? 'RESIDENT_PROPOSAL_MARKED_NEEDS_OFFICIAL_REPORT'
    : 'RESIDENT_PROPOSAL_DISMISSED';
  return audit?.action === expectedAction &&
    audit.proposalId === input.proposalId && audit.rtId === operator.rtId &&
    audit.actorUid === input.operatorUid && audit.commandHash === input.commandHash;
}

function mappingCampaignId(rtId, proposalId) {
  return crypto.createHash('sha256')
    .update(`resident-proposal-campaign\0${rtId}\0${proposalId}`, 'utf8')
    .digest('hex').slice(0, 40);
}

function mappingAuditMatches(audit, input, operator, campaignId) {
  return audit?.auditId === `${input.proposalId}_mapped` &&
    audit.action === 'RESIDENT_PROPOSAL_MAPPED_TO_SAFE_TEMPLATE' &&
    audit.proposalId === input.proposalId && audit.rtId === operator.rtId &&
    audit.actorUid === input.operatorUid && audit.commandHash === input.commandHash &&
    audit.mappingFingerprint === input.mappingFingerprint && audit.campaignId === campaignId &&
    audit.templateId === input.templateId && audit.templateVersion === input.version &&
    asDate(audit.occurredAt) !== null;
}

function storedTemplateSnapshot(value) {
  const allowed = new Set([
    'templateId', 'version', 'title', 'category', 'coreInstruction',
    'safetyInstruction', 'estimatedDurationMinutes',
  ]);
  const validText = (text, limit) => typeof text === 'string' &&
    text === text.normalize('NFC').trim() && text.length > 0 && [...text].length <= limit;
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some((key) => !allowed.has(key)) ||
      typeof value.templateId !== 'string' || !/^[a-z][a-z0-9_-]{0,63}$/u.test(value.templateId) ||
      !Number.isInteger(value.version) || value.version < 1 ||
      !validText(value.title, 120) || !TASK_CATEGORIES.has(value.category) ||
      !validText(value.coreInstruction, 3000) || !validText(value.safetyInstruction, 3000) ||
      (Object.hasOwn(value, 'estimatedDurationMinutes') &&
        (!Number.isInteger(value.estimatedDurationMinutes) ||
          value.estimatedDurationMinutes < 1 || value.estimatedDurationMinutes > 480))) {
    return null;
  }
  return {
    templateId: value.templateId,
    version: value.version,
    title: value.title,
    category: value.category,
    coreInstruction: value.coreInstruction,
    safetyInstruction: value.safetyInstruction,
    ...(Object.hasOwn(value, 'estimatedDurationMinutes') ? {
      estimatedDurationMinutes: value.estimatedDurationMinutes,
    } : {}),
  };
}

function snapshotFingerprint(template) {
  return crypto.createHash('sha256').update(JSON.stringify([
    template.templateId,
    template.version,
    template.title,
    template.category,
    template.coreInstruction,
    template.safetyInstruction,
    template.estimatedDurationMinutes ?? null,
  ]), 'utf8').digest('hex');
}

function campaignMatchesMapping(snapshot, input, operator, campaignId) {
  if (!snapshot.exists) return false;
  const campaign = snapshot.data();
  const templateSnapshot = storedTemplateSnapshot(campaign.templateSnapshot);
  const deadline = asDate(campaign.deadline);
  const createdAt = asDate(campaign.createdAt);
  const activatedAt = campaign.activatedAt == null ? null : asDate(campaign.activatedAt);
  return campaign.campaignId === campaignId && campaign.rtId === operator.rtId &&
    campaign.sourceProposalId === input.proposalId &&
    campaign.createdByOperatorUid === input.operatorUid &&
    campaign.mappedByOperatorUid === input.operatorUid &&
    campaign.mappingCommandHash === input.commandHash &&
    campaign.mappingFingerprint === input.mappingFingerprint &&
    campaign.templateId === input.templateId && campaign.templateVersion === input.version &&
    campaign.templateFingerprint === (templateSnapshot && snapshotFingerprint(templateSnapshot)) &&
    templateSnapshot?.templateId === input.templateId && templateSnapshot.version === input.version &&
    deadline?.toISOString() === input.deadline.toISOString() &&
    (campaign.locationReference ?? null) === input.locationReference && createdAt !== null &&
    (campaign.status === 'DRAFT' ? activatedAt === null :
      campaign.status === 'ACTIVE' && activatedAt !== null);
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
            residentSnapshot.data().deletionPending === true ||
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
    if (!['DISMISSED', 'NEEDS_OFFICIAL_REPORT'].includes(input.decision)) {
      throw fail('invalid-argument', 'Keputusan peninjauan tidak valid.');
    }
    const auditDocId = input.decision === 'NEEDS_OFFICIAL_REPORT'
      ? `${input.proposalId}_official_report`
      : `${input.proposalId}_dismissed`;
    const auditAction = input.decision === 'NEEDS_OFFICIAL_REPORT'
      ? 'RESIDENT_PROPOSAL_MARKED_NEEDS_OFFICIAL_REPORT'
      : 'RESIDENT_PROPOSAL_DISMISSED';

    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const proposalRef = this.firestore.collection(PROPOSAL_COLLECTION).doc(input.proposalId);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(auditDocId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, proposalSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(operatorRef), transaction.get(proposalRef), transaction.get(auditRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      const proposal = proposalFromSnapshot(proposalSnapshot);
      if (!proposal) throw deny();
      if (proposal.rtId !== operator.rtId) throw deny();

      if (proposal.state === input.decision) {
        const storedProposal = proposalSnapshot.data();
        if (storedProposal.reviewDecision === input.decision &&
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
        state: input.decision,
        reviewDecision: input.decision,
        reviewCommandHash: input.commandHash,
        reviewedByOperatorUid: input.operatorUid,
        reviewedAt: input.now,
      };
      transaction.update(proposalRef, update);
      transaction.create(auditRef, {
        auditId: auditDocId,
        proposalId: input.proposalId,
        rtId: operator.rtId,
        action: auditAction,
        decision: input.decision,
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        occurredAt: input.now,
      });
      result = { ...proposalSnapshot.data(), ...update };
    });
    return result;
  }

  async mapProposalToDraft(input) {
    const operatorRef = this.firestore.collection(OPERATOR_COLLECTION).doc(input.operatorUid);
    const proposalRef = this.firestore.collection(PROPOSAL_COLLECTION).doc(input.proposalId);
    const templateRef = this.firestore.collection('task_templates')
      .doc(templateDocumentId(input.templateId, input.version));
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const [operatorSnapshot, proposalSnapshot, templateSnapshot] = await Promise.all([
        transaction.get(operatorRef),
        transaction.get(proposalRef),
        transaction.get(templateRef),
      ]);
      const operator = requireOperator(operatorSnapshot);
      const campaignId = mappingCampaignId(operator.rtId, input.proposalId);
      const campaignRef = this.firestore.collection('task_campaigns').doc(campaignId);
      const auditRef = this.firestore.collection(AUDIT_COLLECTION)
        .doc(`${input.proposalId}_mapped`);
      const [campaignSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(campaignRef), transaction.get(auditRef),
      ]);
      const proposal = proposalFromSnapshot(proposalSnapshot);
      if (!proposal) throw deny();
      if (proposal.rtId !== operator.rtId) throw deny();

      if (proposal.state === 'MAPPED_TO_SAFE_TEMPLATE') {
        const storedProposal = proposalSnapshot.data();
        const campaign = campaignSnapshot.data();
        if (storedProposal.reviewDecision === 'MAPPED_TO_SAFE_TEMPLATE' &&
            storedProposal.mappingCommandHash === input.commandHash &&
            storedProposal.mappingFingerprint === input.mappingFingerprint &&
            storedProposal.reviewedByOperatorUid === input.operatorUid &&
            storedProposal.mappedCampaignId === campaignId &&
            asDate(storedProposal.reviewedAt) && auditSnapshot.exists &&
            mappingAuditMatches(auditSnapshot.data(), input, operator, campaignId) &&
            campaignMatchesMapping(campaignSnapshot, input, operator, campaignId)) {
          result = { proposal: storedProposal, campaign };
          return;
        }
        throw fail('failed-precondition', 'Usulan sudah dipetakan ke draf lain.');
      }
      if (proposal.state !== 'SUBMITTED') {
        throw fail('failed-precondition', 'Usulan tidak menunggu peninjauan.');
      }
      if (campaignSnapshot.exists || auditSnapshot.exists) {
        throw fail('failed-precondition', 'Riwayat pemetaan tidak konsisten.');
      }
      if (templateSnapshot.id !== templateDocumentId(input.templateId, input.version)) {
        throw fail('failed-precondition', 'Template belum disetujui atau tidak aktif.');
      }
      const template = templateSnapshot.exists
        ? approvedTemplateFromRecord(templateSnapshot.data(), input.templateId, input.version)
        : null;
      if (!template) {
        throw fail('failed-precondition', 'Template belum disetujui atau tidak aktif.');
      }
      if (!(input.deadline instanceof Date) || !(input.now instanceof Date) ||
          !Number.isFinite(input.deadline.getTime()) || !Number.isFinite(input.now.getTime()) ||
          input.deadline.getTime() <= input.now.getTime() ||
          (input.locationReference != null &&
            !TASK_LOCATION_REFERENCES.has(input.locationReference))) {
        throw fail('invalid-argument', 'Slot tugas tidak valid.');
      }

      const proposalUpdate = {
        state: 'MAPPED_TO_SAFE_TEMPLATE',
        reviewDecision: 'MAPPED_TO_SAFE_TEMPLATE',
        reviewCommandHash: input.commandHash,
        mappingCommandHash: input.commandHash,
        mappingFingerprint: input.mappingFingerprint,
        mappedCampaignId: campaignId,
        reviewedByOperatorUid: input.operatorUid,
        reviewedAt: input.now,
      };
      const campaignRecord = {
        campaignId,
        rtId: operator.rtId,
        templateId: template.templateId,
        templateVersion: template.version,
        templateFingerprint: template.fingerprint,
        templateSnapshot: publicTemplate(template),
        deadline: input.deadline,
        locationReference: input.locationReference,
        status: 'DRAFT',
        createdByOperatorUid: input.operatorUid,
        mappedByOperatorUid: input.operatorUid,
        sourceProposalId: input.proposalId,
        mappingCommandHash: input.commandHash,
        mappingFingerprint: input.mappingFingerprint,
        createdAt: input.now,
        activatedAt: null,
      };
      transaction.update(proposalRef, proposalUpdate);
      transaction.create(campaignRef, campaignRecord);
      transaction.create(auditRef, {
        auditId: `${input.proposalId}_mapped`,
        proposalId: input.proposalId,
        rtId: operator.rtId,
        action: 'RESIDENT_PROPOSAL_MAPPED_TO_SAFE_TEMPLATE',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        mappingFingerprint: input.mappingFingerprint,
        campaignId,
        templateId: template.templateId,
        templateVersion: template.version,
        occurredAt: input.now,
      });
      result = {
        proposal: { ...proposalSnapshot.data(), ...proposalUpdate },
        campaign: campaignRecord,
      };
    });
    return result;
  }
}

module.exports = { FirestoreResidentProposalRepository };
