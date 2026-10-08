const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { getMessaging } = require('firebase-admin/messaging');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { FirestoreResidentSessionRepository } = require('./firestore_resident_session_repository');
const { FirestoreTaskCampaignRepository } = require('./firestore_task_campaign_repository');
const { FirestoreTaskResponseRepository } = require('./firestore_task_response_repository');
const { FirestoreTaskEvidenceRepository } = require('./firestore_task_evidence_repository');
const { FirestoreResidentProposalRepository } = require('./firestore_resident_proposal_repository');
const { FirestoreEmergencyDirectoryRepository } = require('./firestore_emergency_directory_repository');
const { FirestoreWeatherSuggestionRepository } = require('./firestore_weather_suggestion_repository');
const { FirestoreProxyResidentRepository } = require('./firestore_proxy_resident_repository');
const { FirestoreResidentDataDeletionRepository } = require('./firestore_resident_data_deletion_repository');
const { FirestoreAssistanceAssignmentRepository } = require('./firestore_assistance_assignment_repository');
const { FirestoreTaskNotificationRepository, TaskNotificationError } =
  require('./firestore_task_notification_repository');
const { TaskNotificationService } = require('./task_notification_service');
const { FirebaseMessagingDeliveryAdapter } = require('./task_notification_delivery');
const { fetchBmkgPayload } = require('./bmkg_forecast_client');
const { ResidentSessionService, SessionServiceError } = require('./resident_session_service');
const { TaskCampaignService, TaskCampaignError } = require('./task_campaign_service');
const { TaskResponseService } = require('./task_response_service');
const { TaskEvidenceService } = require('./task_evidence_service');
const { ResidentProposalService, ResidentProposalError } = require('./resident_proposal_service');
const { EmergencyDirectoryService, EmergencyDirectoryError } = require('./emergency_directory_service');
const { WeatherSuggestionService, WeatherPipelineError } = require('./weather_suggestion_service');
const { ProxyResidentService, ProxyResidentError } = require('./proxy_resident_service');
const { ResidentDataDeletionService } = require('./resident_data_deletion_service');
const { AssistanceAssignmentService } = require('./assistance_assignment_service');
const { protectedCallableOptions } = require('./callable_options');
const { UPLOAD_TIMEOUT_SECONDS } = require('./task_evidence_upload_lease');

if (getApps().length === 0) initializeApp();

const firestore = getFirestore();
const sessions = new ResidentSessionService(
  new FirestoreResidentSessionRepository(firestore),
);
const tasks = new TaskCampaignService(
  new FirestoreTaskCampaignRepository(firestore),
);
const taskResponses = new TaskResponseService(
  new FirestoreTaskResponseRepository(firestore),
  sessions,
);
const proxyResidents = new ProxyResidentService(
  new FirestoreProxyResidentRepository(firestore),
);
const residentProposals = new ResidentProposalService(
  new FirestoreResidentProposalRepository(firestore),
  sessions,
);
const emergencyDirectory = new EmergencyDirectoryService(
  new FirestoreEmergencyDirectoryRepository(firestore),
  sessions,
);
const taskEvidenceStorage = {
  assertConfigured() {
    evidenceBucket();
  },
  async save(storagePath, bytes, options) {
    const bucket = evidenceBucket();
    await bucket.file(storagePath).save(bytes, {
      resumable: false,
      metadata: {
        contentType: options.contentType,
        cacheControl: options.cacheControl,
        metadata: { evidenceId: options.evidenceId },
      },
    });
  },
  async delete(storagePath) {
    await evidenceBucket().file(storagePath).delete({ ignoreNotFound: true });
  },
  async read(storagePath) {
    const [bytes] = await evidenceBucket().file(storagePath).download();
    return bytes;
  },
};
const taskEvidence = new TaskEvidenceService(
  new FirestoreTaskEvidenceRepository(firestore),
  sessions,
  taskEvidenceStorage,
);
const residentDataDeletion = new ResidentDataDeletionService(
  new FirestoreResidentDataDeletionRepository(firestore, taskEvidenceStorage),
);
const assistanceAssignments = new AssistanceAssignmentService(
  new FirestoreAssistanceAssignmentRepository(firestore),
  sessions,
);
const weatherSuggestions = new WeatherSuggestionService(
  new FirestoreWeatherSuggestionRepository(firestore),
  { fetchPayload: fetchBmkgPayload },
);
const taskNotifications = new TaskNotificationService(
  new FirestoreTaskNotificationRepository(firestore),
  new FirebaseMessagingDeliveryAdapter(getMessaging()),
  sessions,
);
const callableOptions = protectedCallableOptions();
const evidenceUploadOptions = {
  ...callableOptions,
  maxInstances: 5,
  timeoutSeconds: UPLOAD_TIMEOUT_SECONDS,
  memory: '1GiB',
};

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

exports.getEmergencyDirectory = onCall(callableOptions, async (request) => {
  try {
    return await emergencyDirectory.getEmergencyDirectory(request.data);
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

exports.listActiveTaskCampaigns = onCall(callableOptions, async (request) => {
  try {
    return await tasks.listActiveTaskCampaigns(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listRtTaskHistory = onCall(callableOptions, async (request) => {
  try {
    return await tasks.listRtTaskHistory(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listTaskLifecycleEvents = onCall(callableOptions, async (request) => {
  try {
    return await tasks.listTaskLifecycleEvents(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listWeatherSuggestions = onCall(callableOptions, async (request) => {
  try {
    return await weatherSuggestions.listWeatherSuggestions(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.closeTaskCampaign = onCall(callableOptions, async (request) => {
  try {
    return await tasks.closeTaskCampaign(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.cancelTaskCampaign = onCall(callableOptions, async (request) => {
  try {
    return await tasks.cancelTaskCampaign(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listResidentActiveTasks = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.listResidentActiveTasks(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.recordResidentTaskResponse = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.recordResidentTaskResponse(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.submitTaskCompletion = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.submitTaskCompletion(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.uploadResidentTaskEvidence = onCall(evidenceUploadOptions, async (request) => {
  try {
    return await taskEvidence.uploadResidentEvidence(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.deleteResidentTaskEvidence = onCall(callableOptions, async (request) => {
  try {
    return await taskEvidence.deleteResidentEvidence(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.getTaskEvidenceForVerification = onCall(callableOptions, async (request) => {
  try {
    return await taskEvidence.getEvidenceForOperator(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.deleteExpiredTaskEvidence = onSchedule({
  region: 'asia-southeast2',
  schedule: 'every 24 hours',
  timeZone: 'Etc/UTC',
  maxInstances: 1,
  timeoutSeconds: 120,
}, async () => taskEvidence.deleteExpiredEvidence());

async function runScheduledWeatherSync() {
  const result = await weatherSuggestions.syncConfiguredSources();
  if (result.failed > 0) {
    throw new WeatherPipelineError('unavailable', 'Sebagian sumber BMKG gagal disinkronkan.');
  }
  return result;
}

exports.syncBmkgWeather = onSchedule({
  region: 'asia-southeast2',
  schedule: 'every 6 hours',
  timeZone: 'Etc/UTC',
  maxInstances: 1,
  timeoutSeconds: 120,
}, runScheduledWeatherSync);

const notificationScheduleOptions = {
  region: 'asia-southeast2',
  schedule: 'every 5 minutes',
  timeZone: 'Etc/UTC',
  maxInstances: 1,
  timeoutSeconds: 120,
};
const notificationsEnabled = () => process.env.GUYUB_NOTIFICATIONS_ENABLED === 'true';

exports.sendTaskReminders = onSchedule(notificationScheduleOptions, async () => {
  if (!notificationsEnabled()) return { enabled: false, scheduled: 0, delivered: 0 };
  return taskNotifications.sendTaskReminders();
});

exports.escalateUnrespondedTasks = onSchedule(notificationScheduleOptions, async () => {
  if (!notificationsEnabled()) return { enabled: false, scheduled: 0, delivered: 0 };
  return taskNotifications.escalateUnrespondedTasks();
});

exports.deliverCampaignTransitionNotifications = onSchedule(
  notificationScheduleOptions,
  async () => {
    if (!notificationsEnabled()) return { enabled: false, delivered: 0 };
    return taskNotifications.sendCampaignTransitionNotifications();
  },
);

exports.listPendingTaskVerifications = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.listPendingTaskVerifications(
      operatorAuth(request), request.data,
    );
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.verifyTaskCompletion = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.verifyTaskCompletion(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.getTaskResponseRecap = onCall(callableOptions, async (request) => {
  try {
    return await taskResponses.getTaskResponseRecap(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.createProxyResident = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.createProxyResident(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.cancelPendingProxyResidentCreate = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.cancelPendingProxyResidentCreate(
      operatorAuth(request), request.data,
    );
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listProxyResidents = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.listProxyResidents(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.getProxyTaskStatus = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.getProxyTaskStatus(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.updateProxyResidentAssistance = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.updateProxyAssistance(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.updateProxyTaskStatus = onCall(callableOptions, async (request) => {
  try {
    return await proxyResidents.updateProxyTaskStatus(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.deleteResidentData = onCall(callableOptions, async (request) => {
  try {
    return await residentDataDeletion.deleteResidentData(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.deleteOwnResidentData = onCall(callableOptions, async (request) => {
  try {
    return await residentDataDeletion.deleteOwnResidentData(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.getAssistanceVolunteerData = onCall(callableOptions, async (request) => {
  try {
    return await assistanceAssignments.getVolunteerData(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.updateAssistanceVolunteerConsent = onCall(callableOptions, async (request) => {
  try {
    return await assistanceAssignments.updateVolunteerConsent(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listAvailableAssistanceHelpers = onCall(callableOptions, async (request) => {
  try {
    return await assistanceAssignments.listVolunteerHelpers(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.createAssistanceHelperAssignment = onCall(callableOptions, async (request) => {
  try {
    return await assistanceAssignments.createHelperAssignment(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.respondToAssistanceAssignment = onCall(callableOptions, async (request) => {
  try {
    return await assistanceAssignments.respondToHelperAssignment(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.registerResidentPushToken = onCall(callableOptions, async (request) => {
  try {
    return await taskNotifications.registerResidentPushToken(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.unregisterResidentPushToken = onCall(callableOptions, async (request) => {
  try {
    return await taskNotifications.unregisterResidentPushToken(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.registerPendampingPushToken = onCall(callableOptions, async (request) => {
  try {
    return await taskNotifications.registerPendampingPushToken(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.unregisterPendampingPushToken = onCall(callableOptions, async (request) => {
  try {
    return await taskNotifications.unregisterPendampingPushToken(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listTaskNotificationAudit = onCall(callableOptions, async (request) => {
  try {
    return await taskNotifications.listAuditEvents(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.submitResidentProposal = onCall(callableOptions, async (request) => {
  try {
    return await residentProposals.submitResidentProposal(request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.listResidentProposals = onCall(callableOptions, async (request) => {
  try {
    return await residentProposals.listResidentProposals(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.reviewResidentProposal = onCall(callableOptions, async (request) => {
  try {
    return await residentProposals.reviewResidentProposal(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

exports.mapResidentProposalToDraft = onCall(callableOptions, async (request) => {
  try {
    return await residentProposals.mapResidentProposalToDraft(operatorAuth(request), request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

function evidenceBucket() {
  const projectId = process.env.GCLOUD_PROJECT;
  const bucketName = process.env.GUYUB_EVIDENCE_BUCKET ??
    (process.env.FIREBASE_STORAGE_EMULATOR_HOST && projectId
      ? `${projectId}.appspot.com`
      : null);
  if (typeof bucketName !== 'string' || bucketName.trim().length === 0) {
    throw new TaskCampaignError(
      'failed-precondition',
      'Penyimpanan bukti belum dikonfigurasi.',
    );
  }
  return getStorage().bucket(bucketName.trim());
}

function operatorAuth(request) {
  return {
    operatorUid: request.auth?.uid,
    signInProvider: request.auth?.token?.firebase?.sign_in_provider,
  };
}

function toHttpsError(error) {
  if (error instanceof SessionServiceError || error instanceof TaskCampaignError ||
      error instanceof TaskNotificationError || error instanceof ResidentProposalError ||
      error instanceof EmergencyDirectoryError ||
      error instanceof WeatherPipelineError || error instanceof ProxyResidentError) {
    return new HttpsError(error.code, error.message);
  }
  // Never return Firestore paths, RT existence, or internal error details.
  return new HttpsError('internal', 'Tidak dapat memproses permintaan. Coba lagi.');
}
