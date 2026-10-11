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
const TASK_ID_PATTERN = /^[a-f0-9]{40}$/;
const TASK_LOCATION_REFERENCES = new Set(['COMMUNITY_GENERAL_AREA', 'HOUSEHOLD']);
const DEFAULT_HISTORY_PAGE_SIZE = 25;
const MAX_HISTORY_PAGE_SIZE = 50;
const MAX_HISTORY_CURSOR_LENGTH = 256;

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
  if (typeof value !== 'string' || !TASK_LOCATION_REFERENCES.has(value)) {
    throw invalidArgument('Pilih jenis lokasi umum yang diizinkan.');
  }
  return value;
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

function parseTaskHistoryCursor(value) {
  if (typeof value !== 'string' || value.length === 0 ||
      value.length > MAX_HISTORY_CURSOR_LENGTH || !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw invalidArgument('Kursor riwayat tugas tidak valid.');
  }
  let text;
  let cursor;
  try {
    text = Buffer.from(value, 'base64url').toString('utf8');
    if (Buffer.from(text, 'utf8').toString('base64url') !== value) {
      throw new Error('non-canonical base64url');
    }
    cursor = JSON.parse(text);
  } catch (_) {
    throw invalidArgument('Kursor riwayat tugas tidak valid.');
  }
  if (!cursor || typeof cursor !== 'object' || Array.isArray(cursor) ||
      Object.keys(cursor).length !== 4 || cursor.v !== 1 ||
      !Number.isInteger(cursor.seconds) || cursor.seconds < -62135596800 ||
      cursor.seconds > 253402300799 || !Number.isInteger(cursor.nanoseconds) ||
      cursor.nanoseconds < 0 || cursor.nanoseconds > 999999999 ||
      typeof cursor.campaignId !== 'string' || !TASK_ID_PATTERN.test(cursor.campaignId)) {
    throw invalidArgument('Kursor riwayat tugas tidak valid.');
  }
  return {
    seconds: cursor.seconds,
    nanoseconds: cursor.nanoseconds,
    campaignId: cursor.campaignId,
  };
}

function encodeTaskHistoryCursor(cursor) {
  const token = Buffer.from(JSON.stringify({
    v: 1,
    seconds: cursor.seconds,
    nanoseconds: cursor.nanoseconds,
    campaignId: cursor.campaignId,
  }), 'utf8').toString('base64url');
  if (token.length > MAX_HISTORY_CURSOR_LENGTH) {
    throw failedPrecondition('Riwayat tugas tidak dapat dipaginasi.');
  }
  return token;
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
      'templateId', 'version', 'deadline', 'locationReference', 'requestId',
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
    const requestIdHash = sha256(data.requestId);
    const campaignId = sha256(`${auth.operatorUid}\0${requestIdHash}`).slice(0, 40);
    const requestFingerprint = sha256(JSON.stringify([
      templateId,
      version,
      deadline.toISOString(),
      locationReference,
    ]));
    const campaign = await this.repository.createDraft({
      operatorUid: auth.operatorUid,
      campaignId,
      templateId,
      version,
      deadline,
      locationReference,
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

  async listActiveTaskCampaigns(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const campaigns = await this.repository.listActiveCampaigns(auth.operatorUid);
    return {
      tasks: campaigns.map((campaign) => ({
        taskId: campaign.campaignId,
        templateSnapshot: campaign.templateSnapshot,
        deadline: asDate(campaign.deadline)?.toISOString() ?? null,
        locationReference: campaign.locationReference ?? null,
      })),
    };
  }

  async listRtTaskHistory(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['pageSize', 'cursor']);
    const pageSize = data.pageSize === undefined ? DEFAULT_HISTORY_PAGE_SIZE : data.pageSize;
    if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > MAX_HISTORY_PAGE_SIZE) {
      throw invalidArgument('Ukuran halaman riwayat tugas tidak valid.');
    }
    const cursor = data.cursor === undefined ? null : parseTaskHistoryCursor(data.cursor);
    const page = await this.repository.listRtTaskHistory(auth.operatorUid, {
      pageSize,
      cursor,
    });
    if (!page || !Array.isArray(page.tasks)) {
      throw failedPrecondition('Data riwayat tugas tidak konsisten.');
    }
    return {
      tasks: page.tasks.map((task) => ({
        taskId: task.campaignId,
        templateSnapshot: task.templateSnapshot,
        deadline: asDate(task.deadline)?.toISOString() ?? null,
        locationReference: task.locationReference ?? null,
        status: task.status,
        activatedAt: asDate(task.activatedAt)?.toISOString() ?? null,
        cancelledAt: asDate(task.cancelledAt)?.toISOString() ?? null,
      })),
      nextCursor: page.nextCursor == null ? null : encodeTaskHistoryCursor(page.nextCursor),
    };
  }

  async cancelTaskCampaign(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['taskId', 'commandId']);
    if (typeof data.taskId !== 'string' || !/^[a-f0-9]{40}$/u.test(data.taskId) ||
        typeof data.commandId !== 'string' || !REQUEST_ID_PATTERN.test(data.commandId)) {
      throw invalidArgument('Konfirmasi pembatalan tidak valid.');
    }
    const campaign = await this.repository.cancelCampaign({
      operatorUid: auth.operatorUid,
      taskId: data.taskId,
      commandHash: sha256(data.commandId),
      now: this.clock(),
    });
    return { taskId: data.taskId, status: 'CANCELLED' };
  }
}

module.exports = {
  OPERATOR_ROLES,
  TASK_CATEGORIES,
  TASK_LOCATION_REFERENCES,
  TaskCampaignError,
  TaskCampaignService,
  approvedTemplateFromRecord,
  asDate,
  publicTemplate,
  templateDocumentId,
  templateFingerprint,
};
