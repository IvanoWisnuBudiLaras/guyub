import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';

// applicationId in android/app/build.gradle.kts. Build and install the app
// first (`flutter build apk --debug && flutter install`); the tests open
// whatever is installed under this id.
const app = { bundleId: 'com.guyub.guyub' };

export default {
  // No `agents` block: every test here is deterministic and needs no model.
  targets: [
    {
      name: 'android',
      // Pin the AVD: without it the engine resolves the running emulator's
      // hardware profile name ("sdk gphone64 x86 64"), which is not an AVD.
      engine: mobile({ platform: 'android', device: 'guyub_e2e' }),
      app,
    },
  ],
  // One device, so one worker.
  workers: 1,
} satisfies E2EConfig;
