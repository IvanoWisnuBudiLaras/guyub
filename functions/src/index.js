const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { FirestoreResidentSessionRepository } = require('./firestore_resident_session_repository');
const { FirestoreTaskCampaignRepository } = require('./firestore_task_campaign_repository');
const { ResidentSessionService, SessionServiceError } = require('./resident_session_service');
const { TaskCampaignService, TaskCampaignError } = require('./task_campaign_service');
const { protectedCallableOptions } = require('./callable_options');

if (getApps().length === 0) initializeApp();

const firestore = getFirestore();
const sessions = new ResidentSessionService(
  new FirestoreResidentSessionRepository(firestore),
);
const tasks = new TaskCampaignService(
  new FirestoreTaskCampaignRepository(firestore),
);
const callableOptions = protectedCallableOptions();

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

exports.listApprovedTaskTemplates = onCall(callableOptions, async (request) => {
  try {
    return { templates: await tasks.listApprovedTemplates(operatorAuth(request)) };
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.createTaskDraft = onCall(callableOptions, async (request) => {
  try {
    return await tasks.createDraft(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.activateTaskCampaign = onCall(callableOptions, async (request) => {
  try {
    return await tasks.activateCampaign(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

function operatorAuth(request) {
  return {
    operatorUid: request.auth?.uid,
    signInProvider: request.auth?.token?.firebase?.sign_in_provider,
  };
}

function toHttpsError(error) {
  if (error instanceof SessionServiceError || error instanceof TaskCampaignError) {
    return new HttpsError(error.code, error.message);
  }
  // Never return Firestore paths, RT existence, or internal error details.
  return new HttpsError('internal', 'Tidak dapat memproses permintaan. Coba lagi.');
}
