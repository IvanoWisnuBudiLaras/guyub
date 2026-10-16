// App Check is enforced at the single choke point in src/app.js: invoke().
// These tests prove the gate closes outside the demo emulator and opens only
// there — the same bypass the Cloud Functions path gets from
// `enforceAppCheck: false` on the demo project.
//
//   npx firebase-tools emulators:exec --project demo-guyub-functions \
//     --only firestore "node --test functions/test/app_check_choke_point.test.js"

const test = require('node:test');
const assert = require('node:assert/strict');

const { invoke } = require('../src/app');

// invoke() reads the environment per call, so one process can exercise both
// sides of the gate.
function withEnv(vars, fn) {
  const saved = {};
  for (const [key, value] of Object.entries(vars)) {
    saved[key] = process.env[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    return fn();
  } finally {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

const NON_DEMO = { FUNCTIONS_EMULATOR: undefined, GCLOUD_PROJECT: 'guyub-production' };
const DEMO = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-guyub-functions' };

test('a callable is refused when App Check is required and no token is sent', async () => {
  await withEnv(NON_DEMO, async () => {
    await assert.rejects(
      () => invoke('listActiveTaskCampaigns', { data: {}, auth: undefined }),
      (error) => {
        assert.equal(error.code, 'permission-denied', JSON.stringify(error));
        return true;
      },
    );
  });
});

test('an empty App Check token is refused, not treated as absent-but-fine', async () => {
  await withEnv(NON_DEMO, async () => {
    await assert.rejects(
      () => invoke('listActiveTaskCampaigns', {
        data: {},
        auth: undefined,
        appCheck: { token: '   ' },
      }),
      (error) => {
        assert.equal(error.code, 'permission-denied');
        return true;
      },
    );
  });
});

test('an invalid App Check token is refused, not an internal error', async () => {
  await withEnv(NON_DEMO, async () => {
    await assert.rejects(
      () => invoke('listActiveTaskCampaigns', {
        data: {},
        auth: undefined,
        appCheck: { token: 'not-a-real-app-check-token' },
      }),
      (error) => {
        // Must be a denial the client can act on, never a leaked 500.
        assert.equal(error.code, 'permission-denied', JSON.stringify(error));
        return true;
      },
    );
  });
});

test('the demo emulator is the only place the gate opens', async () => {
  await withEnv(DEMO, async () => {
    // Reaching the service and being refused for a domain reason (no operator
    // membership) proves the App Check gate itself opened.
    await assert.rejects(
      () => invoke('listActiveTaskCampaigns', { data: {}, auth: undefined }),
      (error) => {
        assert.notEqual(error.code, 'internal', JSON.stringify(error));
        assert.notEqual(error.message, 'Permintaan tidak dapat diverifikasi.');
        return true;
      },
    );
  });
});

test('a runtime that already proved App Check passes without a token', async () => {
  await withEnv(NON_DEMO, async () => {
    // This is how the Cloud Functions adapter reports request.app: the platform
    // already verified the token, so re-verifying would be redundant.
    await assert.rejects(
      () => invoke('listActiveTaskCampaigns', {
        data: {},
        auth: undefined,
        appCheck: { verified: true },
      }),
      (error) => {
        assert.notEqual(error.message, 'Permintaan tidak dapat diverifikasi.',
          JSON.stringify(error));
        return true;
      },
    );
  });
});
