const crypto = require('node:crypto');
const { hashSessionToken } = require('./resident_session_service');
const {
  containsDmsCoordinates,
  containsPreciseCoordinates,
  containsNik,
  NIK_PATTERN,
  DECIMAL_COORDINATE_PAIR: COORDINATE_PAIR_PATTERN,
  LABELED_COORDINATE: LABELED_COORDINATE_PATTERN,
} = require('./precise_coordinate_detector');
const { TASK_CATEGORIES, TASK_LOCATION_REFERENCES, OPERATOR_ROLES, asDate } =
  require('./task_campaign_service');

const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;
const PROPOSAL_ID_PATTERN = /^[a-f0-9]{40}$/;
const PROPOSAL_TITLE_LIMIT = 100;
const PROPOSAL_DESCRIPTION_LIMIT = 1000;
const MAX_PENDING_PROPOSALS = 100;
const MOBILE_PATTERN = /(?<!\d)(?:(?:\+?62|0)[\s()./-]*)8(?:[\s()./-]*\d){8,11}(?!\d)/u;
const EXPLICIT_ADDRESS_PATTERN = /\balamat(?:\s+lengkap)?\b/iu;
const STREET_ADDRESS_PATTERN = /\b(?:jalan|jl\.?|gang|gg\.?|blok|perumahan)\s+[\p{L}\p{N}'’.,/-]{1,40}\s+(?:no\.?|nomor|#)?\s*\d{1,4}\b/iu;
const HOUSE_NUMBER_PATTERN = /\brumah\s*(?:#|:)?\s*\d{1,4}\b/iu;

class ResidentProposalError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'ResidentProposalError';
    this.code = code;
  }
}

function invalidArgument(message = 'Usulan tidak valid.') {
  return new ResidentProposalError('invalid-argument', message);
}

function permissionDenied() {
  return new ResidentProposalError('permission-denied', 'Akses usulan tidak valid.');
}

function failedPrecondition(message = 'Usulan tidak dapat ditinjau.') {
  return new ResidentProposalError('failed-precondition', message);
}

function alreadyExists() {
  return new ResidentProposalError('already-exists', 'ID permintaan sudah digunakan.');
}

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    throw invalidArgument();
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw invalidArgument('Permintaan berisi kolom yang tidak diizinkan.');
  }
}

function requireRequestId(value) {
  if (typeof value !== 'string' || !REQUEST_ID_PATTERN.test(value)) {
    throw invalidArgument('ID permintaan tidak valid.');
  }
  return value;
}

function normalizeProposalText(value, field, maxLength) {
  if (typeof value !== 'string') throw invalidArgument(`${field} tidak valid.`);
  const text = value.normalize('NFC').trim();
  const length = [...text].length;
  if (length < 1 || length > maxLength || /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(text)) {
    throw invalidArgument(`${field} tidak valid.`);
  }
  if (containsForbiddenPersonalData(text)) {
    throw invalidArgument('Jangan masukkan koordinat, NIK, nomor ponsel, atau alamat pribadi.');
  }
  return text;
}

function containsForbiddenPersonalData(value) {
  // Parentheses are common formatting around phone/NIK digit groups. Strip them
  // before matching so punctuation cannot hide a number sequence.
  const normalized = value.replace(/[()]/gu, '');
  return containsNik(value) || MOBILE_PATTERN.test(normalized) ||
    containsPreciseCoordinates(value) ||
    EXPLICIT_ADDRESS_PATTERN.test(normalized) || STREET_ADDRESS_PATTERN.test(normalized) ||
    HOUSE_NUMBER_PATTERN.test(normalized);
}

function optionalLocationReference(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || !TASK_LOCATION_REFERENCES.has(value)) {
    throw invalidArgument('Pilih referensi lokasi yang diizinkan.');
  }
  return value;
}

function parseMappingDeadline(value, now) {
  const match = typeof value === 'string' &&
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/u.exec(value);
  if (!match) throw invalidArgument('Batas waktu tugas tidak valid.');
  const [, yearText, monthText, dayText, hourText, minuteText, secondText,
    zone, , offsetHourText, offsetMinuteText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const second = Number(secondText);
  const offsetHour = offsetHourText == null ? 0 : Number(offsetHourText);
  const offsetMinute = offsetMinuteText == null ? 0 : Number(offsetMinuteText);
  const wallClock = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  if (year < 1 || month < 1 || month > 12 || day < 1 ||
      wallClock.getUTCFullYear() !== year || wallClock.getUTCMonth() !== month - 1 ||
      wallClock.getUTCDate() !== day || hour > 23 || minute > 59 || second > 59 ||
      offsetHour > 23 || offsetMinute > 59) {
    throw invalidArgument('Batas waktu tugas tidak valid.');
  }
  const deadline = new Date(value);
  if (!Number.isFinite(deadline.getTime()) || !(now instanceof Date) ||
      !Number.isFinite(now.getTime()) || deadline.getTime() <= now.getTime()) {
    throw invalidArgument('Batas waktu harus berada di masa depan.');
  }
  return deadline;
}

function validateOperatorAuth(auth) {
  if (typeof auth?.operatorUid !== 'string' || auth.operatorUid.trim().length === 0 ||
      auth.signInProvider !== 'password') {
    throw permissionDenied();
  }
}

function proposalDocumentId(rtId, residentId, requestId) {
  return sha256(`resident-proposal\0${rtId}\0${residentId}\0${sha256(requestId)}`).slice(0, 40);
}

function proposalFingerprint({ title, description, category, locationReference }) {
  return sha256(JSON.stringify([title, description, category, locationReference]));
}

function iso(value) {
  const date = asDate(value);
  return date ? date.toISOString() : null;
}

function publicProposal(proposal) {
  return {
    proposalId: proposal.proposalId,
    title: proposal.title,
    description: proposal.description,
    category: proposal.category,
    locationReference: proposal.locationReference ?? null,
    state: proposal.state,
    submittedAt: iso(proposal.submittedAt),
    ...(proposal.state === 'DISMISSED' || proposal.state === 'NEEDS_OFFICIAL_REPORT' || proposal.state === 'MAPPED_TO_SAFE_TEMPLATE'
      ? { reviewedAt: iso(proposal.reviewedAt) } : {}),
  };
}

function publicMappedCampaign(campaign) {
  return {
    campaignId: campaign.campaignId,
    rtId: campaign.rtId,
    templateSnapshot: campaign.templateSnapshot,
    deadline: iso(campaign.deadline),
    locationReference: campaign.locationReference ?? null,
    status: campaign.status,
    createdAt: iso(campaign.createdAt),
    activatedAt: iso(campaign.activatedAt),
  };
}

class ResidentProposalService {
  constructor(repository, residentSessionService, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.residentSessionService = residentSessionService;
    this.clock = clock;
  }

  async submitResidentProposal(data) {
    assertOnlyKeys(data, [
      'sessionToken', 'requestId', 'title', 'description', 'category', 'locationReference',
    ]);
    if (typeof data.sessionToken !== 'string') throw permissionDenied();
    const requestId = requireRequestId(data.requestId);
    const title = normalizeProposalText(data.title, 'Judul usulan', PROPOSAL_TITLE_LIMIT);
    const description = normalizeProposalText(
      data.description, 'Deskripsi usulan', PROPOSAL_DESCRIPTION_LIMIT,
    );
    if (typeof data.category !== 'string' || !TASK_CATEGORIES.has(data.category)) {
      throw invalidArgument('Pilih kategori usulan yang diizinkan.');
    }
    const locationReference = optionalLocationReference(data.locationReference);
    const session = await this.residentSessionService.validateSession(data.sessionToken);
    const now = this.clock();
    const proposalId = proposalDocumentId(session.communityId, session.residentId, requestId);
    const proposal = await this.repository.submitProposal({
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      proposalId,
      title,
      description,
      category: data.category,
      locationReference,
      requestFingerprint: proposalFingerprint({ title, description, category: data.category, locationReference }),
      now,
    });
    return publicProposal(proposal);
  }

  async listResidentProposals(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, []);
    const result = await this.repository.listProposals({ operatorUid: auth.operatorUid });
    return {
      items: result.items.map((item) => ({
        ...publicProposal(item),
        nickname: item.nickname,
      })),
      isPartial: result.isPartial,
    };
  }

  // [status-usulan:kanal-resmi]: Tandai usulan butuh tindak lanjut tanpa mengklaim laporan eksternal terkirim.
  async reviewResidentProposal(auth, data) {
    validateOperatorAuth(auth);
    assertOnlyKeys(data, ['proposalId', 'decision', 'commandId']);
    if (typeof data.proposalId !== 'string' || !PROPOSAL_ID_PATTERN.test(data.proposalId) ||
        !['DISMISSED', 'NEEDS_OFFICIAL_REPORT'].includes(data.decision)) {
      throw invalidArgument('Keputusan peninjauan tidak valid.');
    }
    const commandId = requireRequestId(data.commandId);
    const proposal = await this.repository.reviewProposal({
      operatorUid: auth.operatorUid,
      proposalId: data.proposalId,
      decision: data.decision,
      commandHash: sha256(commandId),
      now: this.clock(),
    });
    return publicProposal(proposal);
  }

  async mapResidentProposalToDraft(auth, data) {
    validateOperatorAuth(auth);
    const requiredKeys = [
      'proposalId', 'templateId', 'version', 'deadline', 'locationReference', 'commandId',
    ];
    assertOnlyKeys(data, requiredKeys);
    if (requiredKeys.some((key) => !Object.prototype.hasOwnProperty.call(data, key))) {
      throw invalidArgument('Kolom pemetaan usulan tidak lengkap.');
    }
    if (typeof data.proposalId !== 'string' || !PROPOSAL_ID_PATTERN.test(data.proposalId)) {
      throw invalidArgument('ID usulan tidak valid.');
    }
    if (typeof data.templateId !== 'string') {
      throw invalidArgument('Template tugas tidak valid.');
    }
    const templateId = data.templateId.normalize('NFC').trim();
    if (!/^[a-z][a-z0-9_-]{0,63}$/u.test(templateId) ||
        !Number.isInteger(data.version) || data.version < 1) {
      throw invalidArgument('Template tugas tidak valid.');
    }
    const commandId = requireRequestId(data.commandId);
    const now = this.clock();
    const deadline = parseMappingDeadline(data.deadline, now);
    const locationReference = optionalLocationReference(data.locationReference);
    const mappingFingerprint = sha256(JSON.stringify([
      templateId, data.version, deadline.toISOString(), locationReference,
    ]));
    const result = await this.repository.mapProposalToDraft({
      operatorUid: auth.operatorUid,
      proposalId: data.proposalId,
      templateId,
      version: data.version,
      deadline,
      locationReference,
      commandHash: sha256(commandId),
      mappingFingerprint,
      now,
    });
    return {
      proposal: publicProposal(result.proposal),
      campaign: publicMappedCampaign(result.campaign),
    };
  }
}

module.exports = {
  REQUEST_ID_PATTERN,
  PROPOSAL_ID_PATTERN,
  PROPOSAL_TITLE_LIMIT,
  PROPOSAL_DESCRIPTION_LIMIT,
  MAX_PENDING_PROPOSALS,
  ResidentProposalError,
  ResidentProposalService,
  containsForbiddenPersonalData,
  normalizeProposalText,
  proposalDocumentId,
  proposalFingerprint,
  publicProposal,
};
