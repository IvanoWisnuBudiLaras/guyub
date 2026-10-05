// Keep the Firestore upload lease longer than the callable's maximum runtime.
const UPLOAD_TIMEOUT_SECONDS = 120;
const UPLOAD_LEASE_MS = 6 * 60 * 1000;

function toDate(value) {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (value && typeof value.toDate === 'function') {
    const date = value.toDate();
    return date instanceof Date && !Number.isNaN(date.getTime()) ? date : null;
  }
  if (value == null) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function hasActiveUploadLease(record, nowValue) {
  const hasExplicitLease = record?.uploadLeaseUntil != null;
  const needsLegacyFallback = record?.status === 'UPLOADING' ||
    (record?.status === 'DELETE_PENDING' && !toDate(record.uploadedAt));
  if (!hasExplicitLease && !needsLegacyFallback) return false;
  const now = toDate(nowValue);
  const createdAt = toDate(record.createdAt);
  const leaseUntil = toDate(record.uploadLeaseUntil) ??
    (createdAt ? new Date(createdAt.getTime() + UPLOAD_LEASE_MS) : null);
  return !now || !leaseUntil || leaseUntil > now;
}

module.exports = {
  UPLOAD_LEASE_MS,
  UPLOAD_TIMEOUT_SECONDS,
  hasActiveUploadLease,
};
