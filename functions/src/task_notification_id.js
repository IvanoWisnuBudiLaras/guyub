const crypto = require('node:crypto');

function sha256(value) {
  return crypto.createHash('sha256').update(value, 'utf8').digest('hex');
}

function residentNotificationRecipientHash(rtId, residentId) {
  return sha256(`task-notification-recipient\0${rtId}\0${residentId}`);
}

function pendampingRecipientHash(rtId) {
  return sha256(`task-notification-role\0${rtId}\0PENDAMPING_RT`);
}

function residentRtRecipientHash(rtId) {
  return sha256(`task-notification-role\0${rtId}\0RESIDENTS_RT`);
}

function notificationEventId({ rtId, campaignId, eventType, windowId, recipientHash }) {
  return sha256([
    'task-notification-event', rtId, campaignId, eventType, windowId, recipientHash,
  ].join('\0')).slice(0, 40);
}

function tokenDocumentId(token) {
  return sha256(`fcm-token\0${token}`);
}

module.exports = {
  notificationEventId,
  pendampingRecipientHash,
  residentRtRecipientHash,
  residentNotificationRecipientHash,
  tokenDocumentId,
};
