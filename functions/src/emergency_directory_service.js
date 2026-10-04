const { hashSessionToken } = require('./resident_session_service');

const DIRECTORY_COLLECTION = 'emergency_directories';
const MAX_DIRECTORY_ITEMS = 10;
const ACCESS_MESSAGE = 'Akses direktori darurat tidak valid.';
const DATA_MESSAGE = 'Direktori darurat tidak valid.';

class EmergencyDirectoryError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'EmergencyDirectoryError';
    this.code = code;
  }
}

function denyAccess() {
  return new EmergencyDirectoryError('permission-denied', ACCESS_MESSAGE);
}

function invalidDirectory() {
  return new EmergencyDirectoryError('failed-precondition', DATA_MESSAGE);
}

function assertOnlyKeys(data, allowedKeys) {
  if (data == null || typeof data !== 'object' || Array.isArray(data)) {
    throw new EmergencyDirectoryError('invalid-argument', 'Permintaan direktori darurat tidak valid.');
  }
  const allowed = new Set(allowedKeys);
  if (Object.keys(data).some((key) => !allowed.has(key))) {
    throw new EmergencyDirectoryError(
      'invalid-argument', 'Permintaan berisi kolom yang tidak diizinkan.',
    );
  }
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

function cleanText(value, maxLength) {
  if (typeof value !== 'string') return null;
  const text = value.normalize('NFC').trim();
  if (text.length === 0 || [...text].length > maxLength ||
      /[\u0000-\u001F\u007F]/u.test(text)) return null;
  return text;
}

function validPhone(value) {
  const phone = cleanText(value, 32);
  if (!phone || !/^\+?[0-9][0-9 ().\/-]*$/u.test(phone)) return null;
  const digits = phone.replace(/\D/gu, '');
  // National emergency short codes (for example 112) are valid contacts too.
  return digits.length >= 3 && digits.length <= 15 ? phone : null;
}

function validHttpsUrl(value) {
  const text = cleanText(value, 2048);
  if (!text) return null;
  try {
    const url = new URL(text);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password) return null;
    return url.toString();
  } catch (_) {
    return null;
  }
}

function exactKeys(value, expected) {
  return value != null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === expected.length &&
    expected.every((key) => Object.prototype.hasOwnProperty.call(value, key));
}

function mapItems(value, validator) {
  if (!Array.isArray(value) || value.length > MAX_DIRECTORY_ITEMS) return null;
  const items = value.map(validator);
  return items.every((item) => item !== null) ? items : null;
}

function validateContact(value) {
  if (!exactKeys(value, ['label', 'phone'])) return null;
  const label = cleanText(value.label, 80);
  const phone = validPhone(value.phone);
  return label && phone ? { label, phone } : null;
}

function validateAssemblyPoint(value) {
  if (!exactKeys(value, ['label', 'publicLocation'])) return null;
  const label = cleanText(value.label, 80);
  const publicLocation = cleanText(value.publicLocation, 240);
  return label && publicLocation ? { label, publicLocation } : null;
}

function validateReportChannel(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) return null;
  const keys = Object.keys(value);
  if (keys.some((key) => !['label', 'url', 'phone'].includes(key)) ||
      !Object.prototype.hasOwnProperty.call(value, 'label') ||
      keys.length < 2 || keys.length > 3) return null;
  const label = cleanText(value.label, 80);
  const hasUrl = Object.prototype.hasOwnProperty.call(value, 'url');
  const hasPhone = Object.prototype.hasOwnProperty.call(value, 'phone');
  const url = hasUrl ? validHttpsUrl(value.url) : null;
  const phone = hasPhone ? validPhone(value.phone) : null;
  if (!label || (!hasUrl && !hasPhone) || (hasUrl && !url) || (hasPhone && !phone)) return null;
  return { label, ...(url ? { url } : {}), ...(phone ? { phone } : {}) };
}

function validateStoredDirectory(record, expectedRtId, now) {
  const keys = [
    'rtId', 'state', 'version', 'lastVerifiedAt', 'emergencyContacts', 'assemblyPoints',
    'officialReportChannels',
  ];
  if (!exactKeys(record, keys) || record.rtId !== expectedRtId ||
      !['ACTIVE', 'DISABLED'].includes(record.state) ||
      !Number.isSafeInteger(record.version) || record.version < 1) {
    throw invalidDirectory();
  }
  const lastVerifiedAt = asDate(record.lastVerifiedAt);
  if (!lastVerifiedAt || lastVerifiedAt.getTime() > now.getTime()) throw invalidDirectory();
  const emergencyContacts = mapItems(record.emergencyContacts, validateContact);
  const assemblyPoints = mapItems(record.assemblyPoints, validateAssemblyPoint);
  const officialReportChannels = mapItems(record.officialReportChannels, validateReportChannel);
  if (!emergencyContacts || !assemblyPoints || !officialReportChannels ||
      (record.state === 'ACTIVE' &&
        (emergencyContacts.length === 0 || assemblyPoints.length === 0))) {
    throw invalidDirectory();
  }

  if (record.state === 'DISABLED') {
    return {
      state: 'DISABLED',
      version: record.version,
      lastVerifiedAt: lastVerifiedAt.toISOString(),
    };
  }
  return {
    state: 'ACTIVE',
    version: record.version,
    lastVerifiedAt: lastVerifiedAt.toISOString(),
    emergencyContacts,
    assemblyPoints,
    officialReportChannels,
  };
}

class EmergencyDirectoryService {
  constructor(repository, residentSessionService, { clock = () => new Date() } = {}) {
    this.repository = repository;
    this.residentSessionService = residentSessionService;
    this.clock = clock;
  }

  async getEmergencyDirectory(data) {
    assertOnlyKeys(data, ['sessionToken']);
    if (typeof data.sessionToken !== 'string') throw denyAccess();

    // The validated server-side session is the only source of resident and RT identity.
    const sessionIdHash = hashSessionToken(data.sessionToken);
    const session = await this.residentSessionService.validateSession(data.sessionToken);
    if (typeof session?.residentId !== 'string' || !session.residentId.trim() ||
        typeof session?.communityId !== 'string' || !session.communityId.trim()) {
      throw denyAccess();
    }

    const now = this.clock();
    const directory = await this.repository.getDirectoryForResident({
      sessionIdHash,
      residentId: session.residentId,
      rtId: session.communityId,
      now,
    });
    if (directory == null) return { state: 'UNCONFIGURED' };
    return validateStoredDirectory(directory, session.communityId, now);
  }
}

module.exports = {
  DIRECTORY_COLLECTION,
  EmergencyDirectoryError,
  EmergencyDirectoryService,
  validateStoredDirectory,
};
