// Runtime-agnostic core: service graph + one invoke() entry point.
//
// The Cloud Functions adapter (index.js) and the HTTP adapter (server/) both
// call invoke(). Nothing here imports firebase-functions, so the same logic
// runs on either runtime.

const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { getMessaging } = require('firebase-admin/messaging');
const { getAppCheck } = require('firebase-admin/app-check');
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
const { FirestoreTreePointRepository } = require('./firestore_tree_point_repository');
const { TreePointService, TreePointError } = require('./tree_point_service');
const dispatch = require('./dispatch');
const { appCheckRequired } = require('./runtime_env');

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
const treePoints = new TreePointService(
  new FirestoreTreePointRepository(firestore),
  sessions,
);

const services = {
  sessions,
  tasks,
  taskResponses,
  proxyResidents,
  residentProposals,
  emergencyDirectory,
  taskEvidence,
  residentDataDeletion,
  assistanceAssignments,
  weatherSuggestions,
  taskNotifications,
  treePoints,
};

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

// The whole authorization surface: a uid and the sign-in provider, both from
// the verified token. Never from the request body.
function operatorAuth(ctx) {
  return {
    operatorUid: ctx.auth?.uid,
    signInProvider: ctx.auth?.signInProvider,
  };
}

const SERVICE_ERRORS = [
  SessionServiceError, TaskCampaignError, TaskNotificationError,
  ResidentProposalError, EmergencyDirectoryError, WeatherPipelineError,
  ProxyResidentError, TreePointError,
];

// Domain error -> { code, message }. Never leaks Firestore paths or internals.
function toServiceError(error) {
  if (SERVICE_ERRORS.some((Type) => error instanceof Type)) {
    return { code: error.code, message: error.message };
  }
  return {
    code: 'internal',
    message: 'Tidak dapat memproses permintaan. Coba lagi.',
  };
}

// The five callables that do not fit the generated table. Each one does
// something the table cannot express: picking fields off `data`, reshaping the
// return, or branching on auth. Kept byte-for-byte equivalent to the original
// src/index.js bodies.
const customCallables = {
  // Takes three named fields, not the whole payload: extra keys are dropped
  // rather than forwarded to the service.
  async createResidentSession(ctx) {
    return sessions.createSession({
      joinCode: ctx.data?.joinCode,
      nickname: ctx.data?.nickname,
      requestId: ctx.data?.requestId,
    });
  },
  // Takes only the token string. Passing the whole `data` here was a real
  // regression once: the service rejects an object where it wants a token.
  async validateResidentSession(ctx) {
    return sessions.validateSession(ctx.data?.sessionToken);
  },
  async revokeResidentSession(ctx) {
    await sessions.revokeSession(ctx.data?.sessionToken);
    return { revoked: true };
  },
  async listApprovedTaskTemplates(ctx) {
    return { templates: await tasks.listApprovedTemplates(operatorAuth(ctx)) };
  },
  async getLastValidWeatherSnapshot(ctx) {
    if (ctx.auth?.uid) {
      return weatherSuggestions.getLastValidWeatherSnapshotForOperator(
        operatorAuth(ctx), ctx.data,
      );
    }
    const data = ctx.data;
    if (data == null || typeof data !== 'object' || Array.isArray(data) ||
        Object.keys(data).some((key) => key !== 'sessionToken')) {
      throw new WeatherPipelineError('invalid-argument', 'Permintaan cuaca tidak valid.');
    }
    const session = await sessions.validateSession(data.sessionToken);
    return weatherSuggestions.getLastValidWeatherSnapshotForRt(session.communityId);
  },
  async listCommunityTreeMap(ctx) {
    if (ctx.auth?.uid) {
      return treePoints.listCommunityTreeMap(operatorAuth(ctx), ctx.data);
    }
    return treePoints.listCommunityTreeMap(null, ctx.data);
  },
  async deleteTreePoint(ctx) {
    if (ctx.auth?.uid) {
      return treePoints.deleteTreePoint(operatorAuth(ctx), ctx.data);
    }
    return treePoints.deleteTreePoint(null, ctx.data);
  },
};

const table = new Map(dispatch.map((row) => [row.name, row]));

const callableNames = Object.freeze([
  ...dispatch.map((row) => row.name),
  ...Object.keys(customCallables),
]);

// App Check is enforced here, at the single choke point every runtime goes
// through, so a new adapter cannot forget it. Cloud Functions additionally
// enforces it at the platform level via `enforceAppCheck`; this is the
// equivalent guarantee for a runtime that does not.
//
// ctx.appCheck is either { verified: true } (the runtime already proved it) or
// { token } for a runtime that must verify it itself.
async function assertAppCheck(ctx) {
  if (!appCheckRequired()) return;
  const proof = ctx.appCheck;
  if (proof?.verified === true) return;
  const token = typeof proof?.token === 'string' ? proof.token.trim() : '';
  if (token.length === 0) throw appCheckDenied();
  try {
    await getAppCheck().verifyToken(token);
  } catch {
    // A bad, expired, or replayed token is a denial, not an internal error.
    throw appCheckDenied();
  }
}

function appCheckDenied() {
  return new TaskCampaignError('permission-denied', 'Permintaan tidak dapat diverifikasi.');
}

// The 5 scheduled jobs. The runtime supplies the schedule; the work lives here
// so Cloud Functions and any other runtime run the same code.
const notificationsEnabled = () => process.env.GUYUB_NOTIFICATIONS_ENABLED === 'true';

const scheduledTasks = Object.freeze({
  deleteExpiredTaskEvidence: () => taskEvidence.deleteExpiredEvidence(),
  syncBmkgWeather: async () => {
    const result = await weatherSuggestions.syncConfiguredSources();
    if (result.failed > 0) {
      throw new WeatherPipelineError('unavailable', 'Sebagian sumber BMKG gagal disinkronkan.');
    }
    return result;
  },
  sendTaskReminders: () => notificationsEnabled()
    ? taskNotifications.sendTaskReminders()
    : { enabled: false, scheduled: 0, delivered: 0 },
  escalateUnrespondedTasks: () => notificationsEnabled()
    ? taskNotifications.escalateUnrespondedTasks()
    : { enabled: false, scheduled: 0, delivered: 0 },
  deliverCampaignTransitionNotifications: () => notificationsEnabled()
    ? taskNotifications.sendCampaignTransitionNotifications()
    : { enabled: false, delivered: 0 },
});

const scheduledTaskNames = Object.freeze(Object.keys(scheduledTasks));

// Callable responses travel as JSON, and `Date` does not survive that trip:
// the Firebase serializer turns it into `{}`, so a client reading a timestamp
// gets an empty object and rejects the whole payload as malformed. Domain
// services legitimately return Dates (they are also written to Firestore,
// where Date is correct), so the conversion belongs here at the boundary
// rather than in every service.
//
// Only own enumerable properties are walked; anything else (Firestore
// Timestamps, Buffers) is passed through untouched for the serializer.
function toWire(value) {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(toWire);
  if (value !== null && typeof value === 'object' &&
      Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, toWire(entry)]),
    );
  }
  return value;
}

// The single entry point both runtimes share.
// ctx = { data, auth: { uid, signInProvider } | undefined, appCheck }
async function invoke(name, ctx) {
  await assertAppCheck(ctx);

  const custom = customCallables[name];
  if (custom) return toWire(await custom(ctx));

  const row = table.get(name);
  if (!row) throw new Error(`Unknown callable: ${name}`);
  const method = services[row.service][row.method];
  if (typeof method !== 'function') {
    throw new Error(`Missing method ${row.service}.${row.method}`);
  }
  const result = row.mode === 'operator'
    ? await method.call(services[row.service], operatorAuth(ctx), ctx.data)
    : await method.call(services[row.service], ctx.data);
  return toWire(result);
}

module.exports = {
  invoke,
  toWire,
  callableNames,
  customCallableNames: Object.freeze(Object.keys(customCallables)),
  scheduledTasks,
  scheduledTaskNames,
  services,
  toServiceError,
  notificationsEnabled,
};
