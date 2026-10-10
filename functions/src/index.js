const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { FirestoreResidentSessionRepository } = require('./firestore_resident_session_repository');
const { ResidentSessionService, SessionServiceError } = require('./resident_session_service');
const { residentCallableOptions } = require('./callable_options');

if (getApps().length === 0) initializeApp();

const sessions = new ResidentSessionService(
  new FirestoreResidentSessionRepository(getFirestore()),
);
const callableOptions = residentCallableOptions();

exports.createResidentSession = onCall(callableOptions, async (request) => {
  try {
    return await sessions.createSession({
      joinCode: request.data?.joinCode,
      nickname: request.data?.nickname,
      requestId: request.data?.requestId,
    });
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.validateResidentSession = onCall(callableOptions, async (request) => {
  try {
    return await sessions.validateSession(request.data?.sessionToken);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.revokeResidentSession = onCall(callableOptions, async (request) => {
  try {
    await sessions.revokeSession(request.data?.sessionToken);
    return { revoked: true };
  } catch (error) {
    throw toHttpsError(error);
  }
});

function toHttpsError(error) {
  if (error instanceof SessionServiceError) {
    return new HttpsError(error.code, error.message);
  }
  // Never return Firestore paths, RT existence, or internal error details.
  return new HttpsError('internal', 'Tidak dapat memproses sesi. Coba lagi.');
}
