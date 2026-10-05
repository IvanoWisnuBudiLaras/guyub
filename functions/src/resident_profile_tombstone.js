const crypto = require('node:crypto');

function residentProfileTombstoneId(rtId, residentId) {
  return crypto.createHash('sha256')
    .update(`resident-profile-tombstone\0${rtId}\0${residentId}`, 'utf8')
    .digest('hex');
}

module.exports = { residentProfileTombstoneId };
