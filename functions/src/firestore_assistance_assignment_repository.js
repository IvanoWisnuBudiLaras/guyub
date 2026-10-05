const crypto = require('node:crypto');
const { OPERATOR_ROLES, asDate } = require('./task_campaign_service');
const { ProxyResidentError } = require('./proxy_resident_service');

const PROFILE_COLLECTION = 'resident_profiles';
const SESSION_COLLECTION = 'resident_sessions';
const ASSIGNMENT_COLLECTION = 'assistance_assignments';
const AUDIT_COLLECTION = 'assistance_assignment_audit_events';
const MAX_ROWS = 200;

function fail(code, message = 'Status bantuan relawan tidak dapat diperbarui.') {
  return new ProxyResidentError(code, message);
}
function deny() { throw fail('permission-denied', 'Akses bantuan relawan tidak valid.'); }
function hash(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}
function requireOperator(snapshot) {
  const operator = snapshot.data();
  if (!snapshot.exists || operator?.active !== true || !OPERATOR_ROLES.has(operator.role) ||
      typeof operator.rtId !== 'string' || !operator.rtId.trim()) deny();
  return { rtId: operator.rtId.trim(), role: operator.role };
}
function requireResidentSession(sessionSnapshot, residentSnapshot, input) {
  const session = sessionSnapshot.data();
  const resident = residentSnapshot.data();
  const expiresAt = asDate(session?.expiresAt);
  if (!sessionSnapshot.exists || session?.active !== true || !expiresAt || expiresAt <= input.now ||
      session.residentId !== input.residentId || session.rtId !== input.rtId ||
      !residentSnapshot.exists || residentSnapshot.id !== input.residentId ||
      resident.rtId !== input.rtId || resident.deletionPending === true ||
      typeof resident.nickname !== 'string') deny();
  return resident;
}
function targetResidentHash(rtId, residentId) {
  return hash(`resident-assistance\0${rtId}\0${residentId}`);
}
function consentAuditId(rtId, residentId, commandHash) {
  return hash(`assistance-volunteer-consent\0${rtId}\0${residentId}\0${commandHash}`).slice(0, 40);
}
function assignmentAuditId(assignmentId, commandHash) {
  return hash(`assistance-assignment-audit\0${assignmentId}\0${commandHash}`).slice(0, 40);
}
function assignmentIdentity(rtId, residentId, helperResidentId, commandHash) {
  return hash(`assistance-assignment\0${rtId}\0${residentId}\0${helperResidentId}\0${commandHash}`)
    .slice(0, 40);
}
function assignmentPairIdentity(rtId, residentId, helperResidentId) {
  return hash(`assistance-assignment-pair\0${rtId}\0${residentId}\0${helperResidentId}`)
    .slice(0, 40);
}
function publicAssignment(snapshot, input) {
  const assignment = snapshot.data();
  const createdAt = asDate(assignment?.createdAt);
  if (!snapshot.exists || assignment.assignmentId !== snapshot.id ||
      assignment.rtId !== input.rtId || assignment.helperResidentId !== input.residentId ||
      !createdAt || !['OFFERED', 'ACCEPTED'].includes(assignment.state)) return null;
  return {
    assignmentId: assignment.assignmentId,
    state: assignment.state,
    createdAt: createdAt.toISOString(),
  };
}
function assignmentAuditMatches(audit, assignmentId, input, rtId) {
  return audit?.auditId === assignmentAuditId(assignmentId, input.commandHash) &&
    audit?.assignmentId === assignmentId && audit.rtId === rtId &&
    audit.commandHash === input.commandHash && audit.action === `ASSISTANCE_ASSIGNMENT_${input.decision}` &&
    audit.residentConsentConfirmed === true && asDate(audit.occurredAt) !== null;
}

class FirestoreAssistanceAssignmentRepository {
  constructor(firestore) { this.firestore = firestore; }

  async getVolunteerData(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(PROFILE_COLLECTION).doc(input.residentId);
    const assignmentsQuery = this.firestore.collection(ASSIGNMENT_COLLECTION)
      .where('rtId', '==', input.rtId)
      .where('helperResidentId', '==', input.residentId)
      .where('state', 'in', ['OFFERED', 'ACCEPTED'])
      .orderBy('createdAt', 'desc')
      .limit(MAX_ROWS + 1);
    return this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, assignmentsSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(assignmentsQuery),
      ]);
      const resident = requireResidentSession(sessionSnapshot, residentSnapshot, input);
      const items = assignmentsSnapshot.docs
        .map((document) => publicAssignment(document, input))
        .filter((item) => item !== null)
        .slice(0, MAX_ROWS);
      return {
        willingToHelp: resident.willingToHelp === true,
        assignments: items,
        isPartial: assignmentsSnapshot.size > MAX_ROWS,
      };
    });
  }

  async updateVolunteerConsent(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(PROFILE_COLLECTION).doc(input.residentId);
    const auditId = consentAuditId(input.rtId, input.residentId, input.commandHash);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(auditId);
    let result;
    await this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, auditSnapshot] = await Promise.all([
        transaction.get(sessionRef), transaction.get(residentRef), transaction.get(auditRef),
      ]);
      const resident = requireResidentSession(sessionSnapshot, residentSnapshot, input);
      if (resident.createdBy !== 'self') deny();
      const audit = auditSnapshot.data();
      const residentHash = targetResidentHash(input.rtId, input.residentId);
      if (auditSnapshot.exists) {
        if (audit.auditId === auditId && audit.action === 'ASSISTANCE_VOLUNTEER_CONSENT_UPDATED' &&
            audit.rtId === input.rtId && audit.targetResidentHash === residentHash &&
            audit.commandHash === input.commandHash &&
            audit.willingToHelp === input.willingToHelp &&
            audit.residentConsentConfirmed === true) {
          result = { willingToHelp: audit.willingToHelp === true };
          return;
        }
        throw fail('already-exists', 'ID permintaan sudah digunakan.');
      }
      transaction.update(residentRef, {
        willingToHelp: input.willingToHelp,
        willingToHelpUpdatedAt: input.now,
        updatedAt: input.now,
      });
      transaction.create(auditRef, {
        auditId,
        action: 'ASSISTANCE_VOLUNTEER_CONSENT_UPDATED',
        rtId: input.rtId,
        targetResidentHash: residentHash,
        actorType: 'RESIDENT',
        commandHash: input.commandHash,
        willingToHelp: input.willingToHelp,
        residentConsentConfirmed: true,
        occurredAt: input.now,
      });
      result = { willingToHelp: input.willingToHelp };
    });
    return result;
  }

  async listVolunteerHelpers({ operatorUid }) {
    const operatorRef = this.firestore.collection('operators').doc(operatorUid);
    return this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      const helpersQuery = this.firestore.collection(PROFILE_COLLECTION)
        .where('rtId', '==', operator.rtId)
        .where('willingToHelp', '==', true)
        .orderBy('createdAt', 'asc')
        .limit(MAX_ROWS + 1);
      const helpersSnapshot = await transaction.get(helpersQuery);
      const items = helpersSnapshot.docs.slice(0, MAX_ROWS).map((document) => {
        const profile = document.data();
        if (profile.rtId !== operator.rtId ||
            profile.createdBy !== 'self' || profile.willingToHelp !== true ||
            profile.deletionPending === true || profile.needsAssistance === true ||
            typeof profile.nickname !== 'string' || !profile.nickname.trim()) return null;
        return { residentId: document.id, nickname: profile.nickname };
      }).filter((item) => item !== null);
      return {
        items,
        isPartial: helpersSnapshot.size > MAX_ROWS || items.length !== helpersSnapshot.size,
      };
    });
  }

  async createHelperAssignment(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    let result;
    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const operator = requireOperator(operatorSnapshot);
      if (input.residentId === input.helperResidentId) deny();
      const residentRef = this.firestore.collection(PROFILE_COLLECTION).doc(input.residentId);
      const helperRef = this.firestore.collection(PROFILE_COLLECTION).doc(input.helperResidentId);
      const [residentSnapshot, helperSnapshot] = await Promise.all([
        transaction.get(residentRef), transaction.get(helperRef),
      ]);
      const resident = residentSnapshot.data();
      const helper = helperSnapshot.data();
      if (!residentSnapshot.exists || residentSnapshot.id !== input.residentId ||
          resident.rtId !== operator.rtId || resident.deletionPending === true ||
          resident.needsAssistance !== true || !helperSnapshot.exists ||
          helperSnapshot.id !== input.helperResidentId || helper.rtId !== operator.rtId ||
          helper.createdBy !== 'self' || helper.deletionPending === true ||
          helper.willingToHelp !== true || helper.needsAssistance === true ||
          typeof helper.nickname !== 'string') deny();

      const assignmentId = assignmentIdentity(
        operator.rtId, input.residentId, input.helperResidentId, input.commandHash,
      );
      const assignmentRef = this.firestore.collection(ASSIGNMENT_COLLECTION).doc(assignmentId);
      const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(`${assignmentId}_created`);
      const pairId = assignmentPairIdentity(operator.rtId, input.residentId, input.helperResidentId);
      const pairGuardRef = this.firestore.collection('assistance_assignment_pair_guards').doc(pairId);
      const [assignmentSnapshot, auditSnapshot, pairGuardSnapshot] = await Promise.all([
        transaction.get(assignmentRef), transaction.get(auditRef), transaction.get(pairGuardRef),
      ]);
      if (assignmentSnapshot.exists) {
        const existing = assignmentSnapshot.data();
        const audit = auditSnapshot.data();
        if (existing.assignmentId === assignmentId && existing.rtId === operator.rtId &&
            existing.residentNeedingHelpId === input.residentId &&
            existing.helperResidentId === input.helperResidentId &&
            existing.commandHash === input.commandHash && audit?.assignmentId === assignmentId &&
            audit.action === 'ASSISTANCE_HELPER_ASSIGNED' && audit.rtId === operator.rtId &&
            audit.commandHash === input.commandHash) {
          result = { assignmentId, state: existing.state };
          return;
        }
        throw fail('already-exists', 'ID permintaan bantuan sudah digunakan.');
      }
      const guard = pairGuardSnapshot.data();
      if (pairGuardSnapshot.exists && typeof guard?.activeAssignmentId === 'string') {
        const activeRef = this.firestore.collection(ASSIGNMENT_COLLECTION)
          .doc(guard.activeAssignmentId);
        const activeSnapshot = await transaction.get(activeRef);
        const active = activeSnapshot.data();
        if (activeSnapshot.exists && active.rtId === operator.rtId &&
            active.residentNeedingHelpId === input.residentId &&
            active.helperResidentId === input.helperResidentId &&
            ['OFFERED', 'ACCEPTED'].includes(active.state)) {
          throw fail('already-exists', 'Pasangan bantuan ini masih aktif.');
        }
      }
      const record = {
        assignmentId,
        rtId: operator.rtId,
        residentNeedingHelpId: input.residentId,
        helperResidentId: input.helperResidentId,
        taskIdOptional: null,
        state: 'OFFERED',
        commandHash: input.commandHash,
        createdByOperatorUid: input.operatorUid,
        createdAt: input.now,
        updatedAt: input.now,
      };
      transaction.create(assignmentRef, record);
      const pairGuard = {
        pairId,
        rtId: operator.rtId,
        residentNeedingHelpId: input.residentId,
        helperResidentId: input.helperResidentId,
        activeAssignmentId: assignmentId,
        updatedAt: input.now,
      };
      if (pairGuardSnapshot.exists) transaction.update(pairGuardRef, pairGuard);
      else transaction.create(pairGuardRef, pairGuard);
      transaction.create(auditRef, {
        auditId: `${assignmentId}_created`,
        action: 'ASSISTANCE_HELPER_ASSIGNED',
        assignmentId,
        rtId: operator.rtId,
        targetResidentHash: targetResidentHash(operator.rtId, input.residentId),
        helperResidentHash: targetResidentHash(operator.rtId, input.helperResidentId),
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        occurredAt: input.now,
      });
      result = { assignmentId, state: 'OFFERED' };
    });
    return result;
  }

  async respondToHelperAssignment(input) {
    const sessionRef = this.firestore.collection(SESSION_COLLECTION).doc(input.sessionIdHash);
    const residentRef = this.firestore.collection(PROFILE_COLLECTION).doc(input.residentId);
    const assignmentRef = this.firestore.collection(ASSIGNMENT_COLLECTION).doc(input.assignmentId);
    const auditId = assignmentAuditId(input.assignmentId, input.commandHash);
    const auditRef = this.firestore.collection(AUDIT_COLLECTION).doc(auditId);
    let result;
    await this.firestore.runTransaction(async (transaction) => {
      const [sessionSnapshot, residentSnapshot, assignmentSnapshot, auditSnapshot] =
        await Promise.all([
          transaction.get(sessionRef), transaction.get(residentRef),
          transaction.get(assignmentRef), transaction.get(auditRef),
        ]);
      const resident = requireResidentSession(sessionSnapshot, residentSnapshot, input);
      if (resident.createdBy !== 'self' || !assignmentSnapshot.exists) deny();
      const assignment = assignmentSnapshot.data();
      if (assignment.assignmentId !== input.assignmentId || assignment.rtId !== input.rtId ||
          assignment.helperResidentId !== input.residentId) deny();
      if (auditSnapshot.exists) {
        if (assignmentAuditMatches(auditSnapshot.data(), input.assignmentId, input, input.rtId)) {
          result = {
            assignmentId: input.assignmentId,
            state: auditSnapshot.data().action.replace('ASSISTANCE_ASSIGNMENT_', ''),
          };
          return;
        }
        throw fail('already-exists', 'ID permintaan sudah digunakan.');
      }
      const pairId = assignmentPairIdentity(
        input.rtId, assignment.residentNeedingHelpId, input.residentId,
      );
      const pairGuardRef = this.firestore.collection('assistance_assignment_pair_guards').doc(pairId);
      const pairGuardSnapshot = await transaction.get(pairGuardRef);
      if (!pairGuardSnapshot.exists ||
          pairGuardSnapshot.data()?.activeAssignmentId !== input.assignmentId) {
        throw fail('failed-precondition', 'Permintaan bantuan sudah berubah.');
      }
      const canAccept = assignment.state === 'OFFERED' && input.decision === 'ACCEPTED' &&
        resident.willingToHelp === true;
      const canDecline = assignment.state === 'OFFERED' && input.decision === 'DECLINED';
      const canWithdraw = assignment.state === 'ACCEPTED' && input.decision === 'WITHDRAWN';
      if (!canAccept && !canDecline && !canWithdraw) {
        throw fail('failed-precondition', 'Permintaan bantuan sudah berubah.');
      }
      transaction.update(assignmentRef, {
        state: input.decision,
        respondedAt: input.now,
        updatedAt: input.now,
        responseCommandHash: input.commandHash,
      });
      if (input.decision === 'DECLINED' || input.decision === 'WITHDRAWN') {
        transaction.update(pairGuardRef, {
          activeAssignmentId: null,
          updatedAt: input.now,
        });
      }
      transaction.create(auditRef, {
        auditId,
        action: `ASSISTANCE_ASSIGNMENT_${input.decision}`,
        assignmentId: input.assignmentId,
        rtId: input.rtId,
        actorType: 'HELPER',
        actorResidentHash: targetResidentHash(input.rtId, input.residentId),
        commandHash: input.commandHash,
        residentConsentConfirmed: true,
        occurredAt: input.now,
      });
      result = { assignmentId: input.assignmentId, state: input.decision };
    });
    return result;
  }
}

module.exports = {
  ASSIGNMENT_COLLECTION,
  FirestoreAssistanceAssignmentRepository,
  assignmentIdentity,
  assignmentPairIdentity,
};
