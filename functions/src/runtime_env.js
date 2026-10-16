// Runtime environment facts shared by every adapter.
//
// Both the Cloud Functions adapter and the HTTP adapter must agree on when
// App Check is enforced, or one of them silently becomes the weak link.

// The demo emulator project is the only place App Check is skipped: it is how
// the local test suites and `emulators:exec` run without real App Check tokens.
function isDemoEmulator(env = process.env) {
  return env.FUNCTIONS_EMULATOR === 'true' &&
    typeof env.GCLOUD_PROJECT === 'string' &&
    env.GCLOUD_PROJECT.startsWith('demo-');
}

// App Check is required everywhere except the demo emulator.
function appCheckRequired(env = process.env) {
  return !isDemoEmulator(env);
}

module.exports = { isDemoEmulator, appCheckRequired };
