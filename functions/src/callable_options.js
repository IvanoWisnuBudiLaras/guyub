const { appCheckRequired } = require('./runtime_env');

function protectedCallableOptions(environment = process.env) {
  return {
    region: 'asia-southeast2',
    maxInstances: 20,
    timeoutSeconds: 15,
    // Skipped only on the demo emulator, where no App Check token exists.
    enforceAppCheck: appCheckRequired(environment),
  };
}

const residentCallableOptions = protectedCallableOptions;

module.exports = { protectedCallableOptions, residentCallableOptions };
