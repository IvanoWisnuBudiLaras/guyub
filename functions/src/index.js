// Cloud Functions adapter.
//
// All behaviour lives in src/app.js. This file only declares the runtime shape:
// which callables exist, which options each gets, and the 5 schedules. Both the
// callable list and the per-callable options come from the generated table, so
// adding a callable to index.js cannot drift from this adapter.

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  invoke,
  toServiceError,
  scheduledTasks,
  scheduledTaskNames,
} = require('./app');
const dispatch = require('./dispatch');
const { protectedCallableOptions } = require('./callable_options');
const {
  taskWindowNotificationScheduleOptions,
  lifecycleNotificationScheduleOptions,
} = require('./task_notification_schedule');
const { UPLOAD_TIMEOUT_SECONDS } = require('./task_evidence_upload_lease');

const callableOptions = protectedCallableOptions();
const evidenceUploadOptions = {
  ...callableOptions,
  maxInstances: 5,
  timeoutSeconds: UPLOAD_TIMEOUT_SECONDS,
  memory: '1GiB',
};
const optionsByName = {
  callableOptions,
  evidenceUploadOptions,
};

// Mirrors the old inline `operatorAuth(request)`: the uid and sign-in provider
// come from the verified token, never from the request body.
function requestAuth(request) {
  return {
    uid: request.auth?.uid,
    signInProvider: request.auth?.token?.firebase?.sign_in_provider,
  };
}

function registerCallable(name, options) {
  exports[name] = onCall(options, async (request) => {
    try {
      return await invoke(name, {
        data: request.data,
        auth: requestAuth(request),
        // `enforceAppCheck` already rejected an unverified caller at the
        // platform level, so a present app claim is the proof. Absent one,
        // app.js enforces it again — fail closed if the two ever diverge.
        appCheck: request.app ? { verified: true } : undefined,
      });
    } catch (error) {
      const { code, message } = toServiceError(error);
      throw new HttpsError(code, message);
    }
  });
}

for (const row of dispatch) {
  registerCallable(row.name, optionsByName[row.options] ?? callableOptions);
}

// The five callables whose bodies do not fit the generated table. Their work
// lives in app.js; they are listed here only so the runtime exposes them.
for (const name of ['createResidentSession', 'validateResidentSession',
  'revokeResidentSession', 'listApprovedTaskTemplates',
  'getLastValidWeatherSnapshot']) {
  registerCallable(name, callableOptions);
}

const schedules = {
  deleteExpiredTaskEvidence: {
    region: 'asia-southeast2',
    schedule: 'every 24 hours',
    timeZone: 'Etc/UTC',
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  syncBmkgWeather: {
    region: 'asia-southeast2',
    schedule: 'every 6 hours',
    timeZone: 'Etc/UTC',
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  sendTaskReminders: taskWindowNotificationScheduleOptions,
  escalateUnrespondedTasks: taskWindowNotificationScheduleOptions,
  deliverCampaignTransitionNotifications: lifecycleNotificationScheduleOptions,
};

for (const name of scheduledTaskNames) {
  exports[name] = onSchedule(schedules[name], () => scheduledTasks[name]());
}
