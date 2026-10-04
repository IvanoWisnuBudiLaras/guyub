const {
  OPERATOR_ROLES,
  TaskCampaignError,
  approvedTemplateFromRecord,
  asDate,
  publicTemplate,
  templateDocumentId,
} = require('./task_campaign_service');

function denyOperator() {
  return new TaskCampaignError('permission-denied', 'Akses operator tidak valid.');
}

function requireOperator(snapshot) {
  const data = snapshot.data();
  if (!snapshot.exists || data?.active !== true || !OPERATOR_ROLES.has(data.role) ||
      typeof data.rtId !== 'string' || data.rtId.trim().length === 0) {
    throw denyOperator();
  }
  return { rtId: data.rtId.trim(), role: data.role };
}

function templateFromSnapshot(snapshot, templateId, version) {
  if (!snapshot.exists) return null;
  return approvedTemplateFromRecord(snapshot.data(), templateId, version);
}

function campaignTemplateMatches(campaign, template) {
  if (!campaign || !template || campaign.templateFingerprint !== template.fingerprint ||
      !campaign.templateSnapshot || typeof campaign.templateSnapshot !== 'object') {
    return false;
  }
  const expected = publicTemplate(template);
  const actual = campaign.templateSnapshot;
  return JSON.stringify(Object.keys(expected).sort().map((key) => [key, expected[key]])) ===
    JSON.stringify(Object.keys(actual).sort().map((key) => [key, actual[key]]));
}

class FirestoreTaskCampaignRepository {
  constructor(firestore) {
    this.firestore = firestore;
  }

  async listApprovedTemplates(operatorUid) {
    const operatorSnapshot = await this.firestore.collection('operators').doc(operatorUid).get();
    requireOperator(operatorSnapshot);

    const templates = await this.firestore.collection('task_templates')
      .where('reviewStatus', '==', 'approved')
      .get();
    return templates.docs
      .map((snapshot) => {
        const record = snapshot.data();
        if (snapshot.id !== templateDocumentId(record.templateId, record.version)) {
          return null;
        }
        return approvedTemplateFromRecord(record, record.templateId, record.version);
      })
      .filter((template) => template !== null)
      .sort((left, right) => left.templateId.localeCompare(right.templateId))
      .map((template) => ({
        templateId: template.templateId,
        version: template.version,
        title: template.title,
        category: template.category,
        coreInstruction: template.coreInstruction,
        safetyInstruction: template.safetyInstruction,
        ...(template.estimatedDurationMinutes == null ? {} : {
          estimatedDurationMinutes: template.estimatedDurationMinutes,
        }),
        fingerprint: template.fingerprint,
      }));
  }

  async createDraft(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const templateRef = this.firestore.collection('task_templates')
      .doc(templateDocumentId(input.templateId, input.version));
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const templateSnapshot = await transaction.get(templateRef);
      const campaignSnapshot = await transaction.get(campaignRef);
      const operator = requireOperator(operatorSnapshot);
      if (campaignSnapshot.exists) {
        const existing = campaignSnapshot.data();
        if (existing.createdByOperatorUid !== input.operatorUid ||
            existing.rtId !== operator.rtId ||
            existing.requestFingerprint !== input.requestFingerprint ||
            !['DRAFT', 'ACTIVE'].includes(existing.status)) {
          throw new TaskCampaignError(
            'already-exists',
            'Permintaan pembuatan tugas sudah digunakan.',
          );
        }
        result = existing;
        return;
      }

      const template = templateFromSnapshot(templateSnapshot, input.templateId, input.version);
      if (!template) {
        throw new TaskCampaignError(
          'failed-precondition',
          'Template belum disetujui atau tidak aktif.',
        );
      }
      if (!(input.deadline instanceof Date) || input.deadline.getTime() <= input.now.getTime()) {
        throw new TaskCampaignError('invalid-argument', 'Batas waktu tugas harus di masa depan.');
      }

      result = {
        campaignId: input.campaignId,
        rtId: operator.rtId,
        templateId: template.templateId,
        templateVersion: template.version,
        templateFingerprint: template.fingerprint,
        templateSnapshot: publicTemplate(template),
        deadline: input.deadline,
        locationReference: input.locationReference,
        additionalNote: input.additionalNote,
        status: 'DRAFT',
        createdByOperatorUid: input.operatorUid,
        createdAt: input.now,
        requestFingerprint: input.requestFingerprint,
      };
      transaction.create(campaignRef, result);
    });
    return result;
  }

  async activateCampaign(input) {
    const operatorRef = this.firestore.collection('operators').doc(input.operatorUid);
    const campaignRef = this.firestore.collection('task_campaigns').doc(input.campaignId);
    const auditRef = this.firestore.collection('task_audit_events')
      .doc(`${input.campaignId}_activated`);
    let result;

    await this.firestore.runTransaction(async (transaction) => {
      const operatorSnapshot = await transaction.get(operatorRef);
      const campaignSnapshot = await transaction.get(campaignRef);
      const operator = requireOperator(operatorSnapshot);
      if (!campaignSnapshot.exists) {
        throw new TaskCampaignError('not-found', 'Tugas tidak ditemukan.');
      }
      const campaign = campaignSnapshot.data();
      if (campaign.rtId !== operator.rtId) throw denyOperator();
      const auditSnapshot = await transaction.get(auditRef);

      if (campaign.status === 'ACTIVE') {
        if (campaign.activationCommandHash === input.commandHash &&
            campaign.activatedByOperatorUid === input.operatorUid &&
            auditSnapshot.exists &&
            auditSnapshot.data().actorUid === input.operatorUid &&
            auditSnapshot.data().commandHash === input.commandHash) {
          result = campaign;
          return;
        }
        throw new TaskCampaignError('failed-precondition', 'Tugas sudah diaktifkan.');
      }
      if (campaign.status !== 'DRAFT') {
        throw new TaskCampaignError('failed-precondition', 'Hanya draf yang dapat diaktifkan.');
      }
      if (auditSnapshot.exists) {
        throw new TaskCampaignError('failed-precondition', 'Riwayat aktivasi tidak konsisten.');
      }
      const deadline = asDate(campaign.deadline);
      if (!deadline || deadline.getTime() <= input.now.getTime()) {
        throw new TaskCampaignError('failed-precondition', 'Batas waktu tugas sudah lewat.');
      }

      const templateRef = this.firestore.collection('task_templates')
        .doc(templateDocumentId(campaign.templateId, campaign.templateVersion));
      const templateSnapshot = await transaction.get(templateRef);
      const template = templateFromSnapshot(
        templateSnapshot,
        campaign.templateId,
        campaign.templateVersion,
      );
      if (!campaignTemplateMatches(campaign, template)) {
        throw new TaskCampaignError(
          'failed-precondition',
          'Template berubah, dinonaktifkan, atau tidak lagi disetujui.',
        );
      }

      const activated = {
        ...campaign,
        status: 'ACTIVE',
        activatedAt: input.now,
        activatedByOperatorUid: input.operatorUid,
        activationCommandHash: input.commandHash,
      };
      transaction.update(campaignRef, {
        status: activated.status,
        activatedAt: activated.activatedAt,
        activatedByOperatorUid: activated.activatedByOperatorUid,
        activationCommandHash: activated.activationCommandHash,
      });
      transaction.create(auditRef, {
        campaignId: input.campaignId,
        rtId: operator.rtId,
        action: 'CAMPAIGN_ACTIVATED',
        actorUid: input.operatorUid,
        commandHash: input.commandHash,
        templateId: campaign.templateId,
        templateVersion: campaign.templateVersion,
        occurredAt: input.now,
      });
      result = activated;
    });
    return result;
  }
}

module.exports = { FirestoreTaskCampaignRepository };
