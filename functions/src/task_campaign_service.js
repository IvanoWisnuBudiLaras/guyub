const crypto = require('node:crypto');

const OPERATOR_ROLES = new Set(['KETUA_RT_RW', 'PENDAMPING_RT']);
const TASK_CATEGORIES = new Set([
  'HOUSEHOLD_PREPARATION',
  'LOGISTICS',
  'ENVIRONMENTAL_CLEANUP',
  'SAFE_VISUAL_INSPECTION',
]);
const TEMPLATE_ID_PATTERN = /^[a-z][a-z0-9_-]{0,63}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const MAX_LOCATION_REFERENCE_LENGTH = 120;
const MAX_ADDITIONAL_NOTE_LENGTH = 160;

class TaskCampaignError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'TaskCampaignError';
    this.code = code;
  }
}

function invalidArgument(message) {
  return new TaskCampaignError('invalid-argument', message);
}

function permissionDenied() {
  return new TaskCampaignError('permission-denied', 'Akses operator tidak valid.');
}

function failedPrecondition(message = 'Tugas tidak dapat diaktifkan.') {
  return new TaskCampaignError('failed-precondition', message);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function validateOperatorAuth({ operatorUid, signInProvider }) {
  if (typeof operatorUid !== 'string' || operatorUid.trim().length === 0 ||
      signInProvider !== 'password') {
    throw permissionDenied();
  }
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    throw invalidArgument('Permintaan tugas tidak valid.');
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw invalidArgument('Permintaan tugas berisi kolom yang tidak diizinkan.');
  }
}

function requiredText(value, field, maxLength) {
  if (typeof value !== 'string') throw invalidArgument(`${field} tidak valid.`);
  const text = value.normalize('NFC').trim();
  if (text.length === 0 || [...text].length > maxLength ||
      /[\u0000-\u001F\u007F]/u.test(text)) {
    throw invalidArgument(`${field} tidak valid.`);
  }
  return text;
}

function optionalLocationReference(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw invalidArgument('Lokasi tugas tidak valid.');
  const location = value.normalize('NFC').trim();
  if (location.length === 0) return null;
  if ([...location].length > MAX_LOCATION_REFERENCE_LENGTH ||
      /[\u0000-\u001F\u007F]/u.test(location) ||
      /-?\d{1,3}\.\d{3,}\s*[,; ]\s*-?\d{1,3}\.\d{3,}/u.test(location) ||
      /\b(?:alamat|rumah|jalan|jl\.?|gang|gg\.?|blok|perumahan)\b/iu.test(location) ||
      /\b(?:no\.?|nomor)\s*\d/iu.test(location)) {
    throw invalidArgument('Gunakan lokasi umum tanpa alamat rumah atau koordinat GPS.');
  }
  return location;
}

function optionalAdditionalNote(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw invalidArgument('Catatan tambahan tidak valid.');
  const note = value.normalize('NFC').trim();
  if (note.length === 0) return null;
  if ([...note].length > MAX_ADDITIONAL_NOTE_LENGTH ||
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(note) ||
      /-?\d{1,3}\.\d{3,}\s*[,; ]\s*-?\d{1,3}\.\d{3,}/u.test(note) ||
      /\b(?:alamat|rumah|jalan|jl\.?|gang|gg\.?|blok|perumahan)\b/iu.test(note) ||
      /\b(?:no\.?|nomor)\s*\d/iu.test(note)) {
    throw invalidArgument('Gunakan catatan singkat tanpa alamat rumah atau koordinat GPS.');
  }
  return note;
}

function parseFutureDeadline(value, now) {
  if (typeof value !== 'string' || !/^\d{4}-\d\d-\d\dT.*(?:Z|[+-]\d\d:\d\d)$/u.test(value)) {
    throw invalidArgument('Batas waktu tugas tidak valid.');
  }
  const deadline = new Date(value);
  if (!Number.isFinite(deadline.getTime()) || deadline.getTime() <= now.getTime()) {
    throw invalidArgument('Batas waktu harus berada di masa depan.');
  }
  return deadline;
}

function templateDocumentId(templateId, version) {
  return `${templateId}_v${version}`;
}

function templateFingerprint(template) {
  return sha256(JSON.stringify([
    template.templateId,
    template.version,
    template.title,
    template.category,
    template.coreInstruction,
    template.safetyInstruction,
    template.estimatedDurationMinutes ?? null,
  ]));
}

function asDate(value) {
  if (value instanceof Date) return value;
  if (value && typeof value.toDate === 'function') return value.toDate();
  if (typeof value === 'string') {
    const parsed = new Date(value);
    return Number.isFinite(parsed.getTime()) ? parsed : null;
  }
  return null;
}

function approvedTemplateFromRecord(record, expectedId, expectedVersion) {
  if (!record || record.reviewStatus !== 'approved' || record.enabled !== true ||
      record.templateId !== expectedId || record.version !== expectedVersion ||
      typeof record.reviewedBy !== 'string' || record.reviewedBy.trim().length === 0 ||
      !asDate(record.reviewedAt) || !TEMPLATE_ID_PATTERN.test(expectedId) ||
      !Number.isInteger(expectedVersion) || expectedVersion < 1 ||
      typeof record.title !== 'string' || typeof record.category !== 'string' ||
      typeof record.coreInstruction !== 'string' ||
      typeof record.safetyInstruction !== 'string') {
    return null;
  }

  const title = record.title.normalize('NFC').trim();
  const category = record.category.trim();
  const coreInstruction = record.coreInstruction.normalize('NFC').trim();
  const safetyInstruction = record.safetyInstruction.normalize('NFC').trim();
  const duration = record.estimatedDurationMinutes;
  if (title.length === 0 || [...title].length > 120 ||
      !TASK_CATEGORIES.has(category) || coreInstruction.length === 0 ||
      [...coreInstruction].length > 3000 || safetyInstruction.length === 0 ||
      [...safetyInstruction].length > 3000 ||
      (duration != null && (!Number.isInteger(duration) || duration < 1 || duration > 480))) {
    return null;
  }

  const template = {
    templateId: expectedId,
    version: expectedVersion,
    title,
    category,
    coreInstruction,
    safetyInstruction,
    ...(duration == null ? {} : { estimatedDurationMinutes: duration }),
  };
  return { ...template, fingerprint: templateFingerprint(template) };
}

function publicTemplate(template) {
  return {
    templateId: template.templateId,
    version: template.version,
    title: template.title,
    category: template.category,
    coreInstruction: template.coreInstruction,
    safetyInstruction: template.safetyInstruction,
    ...(template.estimatedDurationMinutes == null ? {} : {
      estimatedDurationMinutes: template.estimatedDurationMinutes,
    }),
  };
}

function publicCampaign(campaign) {
  const dateValue = (value) => {
    const parsed = asDate(value);
    return parsed ? parsed.toISOString() : null;
  };
  return {
    campaignId: campaign.campaignId,
    rtId: campaign.rtId,
    templateSnapshot: campaign.templateSnapshot,
    deadline: dateValue(campaign.deadline),
    locationReference: campaign.locationReference ?? null,
    additionalNote: campaign.additionalNote ?? null,
    status: campaign.status,
    createdAt: dateValue(campaign.createdAt),
    activatedAt: dateValue(campaign.activatedAt),
  };
}

class TaskCampaignService {
  constructor(repository, {
    clock = () => new Date(),
  } = {}) {
    this.repository = repository;
    this.clock = clock;
  }

  async listApprovedTemplates(auth) {
    validateOperatorAuth(auth);
    const templates = await this.repository.listApprovedTemplates(auth.operatorUid);
    return templates.map(({ fingerprint, ...template }) => template);
  }

  async createDraft(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, [
      'templateId', 'version', 'deadline', 'locationReference',
      'additionalNote', 'requestId',
    ]);
    const templateId = requiredText(data.templateId, 'Template', 64);
    const version = data.version;
    if (!TEMPLATE_ID_PATTERN.test(templateId) || !Number.isInteger(version) || version < 1) {
      throw invalidArgument('Template tugas tidak valid.');
    }
    if (typeof data.requestId !== 'string' || !REQUEST_ID_PATTERN.test(data.requestId)) {
      throw invalidArgument('Permintaan tugas tidak valid.');
    }
    const now = this.clock();
    const deadline = parseFutureDeadline(data.deadline, now);
    const locationReference = optionalLocationReference(data.locationReference);
    const additionalNote = optionalAdditionalNote(data.additionalNote);
    const requestIdHash = sha256(data.requestId);
    const campaignId = sha256(`${auth.operatorUid}\0${requestIdHash}`).slice(0, 40);
    const requestFingerprint = sha256(JSON.stringify([
      templateId,
      version,
      deadline.toISOString(),
      locationReference,
      additionalNote,
    ]));
    const campaign = await this.repository.createDraft({
      operatorUid: auth.operatorUid,
      campaignId,
      templateId,
      version,
      deadline,
      locationReference,
      additionalNote,
      now,
      requestFingerprint,
    });
    return publicCampaign(campaign);
  }

  async activateCampaign(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['campaignId', 'commandId']);
    if (typeof data.campaignId !== 'string' || !/^[a-f0-9]{40}$/u.test(data.campaignId) ||
        typeof data.commandId !== 'string' || !REQUEST_ID_PATTERN.test(data.commandId)) {
      throw invalidArgument('Konfirmasi aktivasi tidak valid.');
    }
    const campaign = await this.repository.activateCampaign({
      operatorUid: auth.operatorUid,
      campaignId: data.campaignId,
      commandHash: sha256(data.commandId),
      now: this.clock(),
    });
    return publicCampaign(campaign);
  }
}

module.exports = {
  MAX_ADDITIONAL_NOTE_LENGTH,
  MAX_LOCATION_REFERENCE_LENGTH,
  OPERATOR_ROLES,
  TASK_CATEGORIES,
  TaskCampaignError,
  TaskCampaignService,
  approvedTemplateFromRecord,
  asDate,
  publicTemplate,
  templateDocumentId,
  templateFingerprint,
};
