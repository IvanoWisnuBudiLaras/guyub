function residentCallableOptions(environment = process.env) {
  const isDemoEmulator = environment.FUNCTIONS_EMULATOR === 'true' &&
    typeof environment.GCLOUD_PROJECT === 'string' &&
    environment.GCLOUD_PROJECT.startsWith('demo-');
  return {
    region: 'asia-southeast2',
    maxInstances: 20,
    timeoutSeconds: 15,
    enforceAppCheck: !isDemoEmulator,
  };
}

module.exports = { residentCallableOptions };
