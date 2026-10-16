import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// AT-006 / O-01: an active task and its locked safety instruction must stay
// readable with no network, and the UI must say the data is cached rather than
// presenting it as live.
//
// The RT, catalog template, and ACTIVE campaign are seeded before the run by
// functions/test/seed_e2e_campaign.js, which goes through the real callables.
//
// Runs against the Firebase emulator suite on the host (10.0.2.2 from the
// emulator); `tool/test_e2e_offline_task.sh` starts both and clears the app's
// data first, so the first test always sees the enrollment form.
//
// Note on locators: Flutter widget `Key`s are not visible to the driver, and
// several screens render a label plus its detail inside one accessibility node.
// Locators here therefore use visible text, matched as substrings where the
// node joins several lines.

const JOIN_CODE = 'GUYUBE2E2026';
const TASK_TITLE = 'Persiapan rumah tangga';
const TASK_ROW = new RegExp(TASK_TITLE);
const SAFETY_TEXT = new RegExp(
  'Jangan mendekati air banjir atau instalasi listrik basah',
);

type Screen = {
  getByText: (text: string | RegExp) => {
    tap: () => Promise<void>;
    isVisible: () => Promise<boolean>;
    first: () => { tap: () => Promise<void> };
  };
  getByPlaceholder: (text: string) => {
    fill: (value: string) => Promise<void>;
    isVisible: () => Promise<boolean>;
  };
};

// Opens the app and ends on the task list, whether or not a session was already
// stored. Enrollment only happens when the form is actually on screen, so the
// tests do not depend on each other's leftover state.
async function openTaskList(
  app: { open: () => Promise<void>; restart: () => Promise<void> },
  screen: Screen,
  nickname: string,
  { restart = false }: { restart?: boolean } = {},
) {
  if (restart) await app.restart();
  else await app.open();

  // Role selection is shown when no session was restored.
  if (await screen.getByText('Saya Warga').isVisible()) {
    await screen.getByText('Saya Warga').tap();
  }

  // Either the enrollment form appears, or a stored session is restored and the
  // home screen appears. The runner clears app data before the suite, so on the
  // first test the form is what shows; later tests may restore a session.
  await expect(
    screen.getByPlaceholder('Kode RT'),
  ).toBeVisible({ timeout: 30_000 });

  await screen.getByPlaceholder('Kode RT').fill(JOIN_CODE);
  await screen.getByPlaceholder('Nama panggilan').fill(nickname);
  await screen.getByText('Masuk ke RT').tap();

  // Enrollment lands on the home screen; the task list is one tap further.
  await screen.getByText('Lihat Tugas Kesiapsiagaan').tap();
}

// Signs the resident out so the next test starts at role selection with no
// stored session. Uses the app's own "Keluar" action, which clears the local
// session without deleting server data. `app.clearState()` is not used: it
// destabilises this emulator (the package manager service dies).
async function signOut(app: { open: () => Promise<void> }, screen: Screen) {
  await app.open();
  // Role selection means the session is already gone; nothing to do.
  if (await screen.getByText('Saya Warga').isVisible()) return;
  await screen.getByText('Keluar').tap();
  await expect(screen.getByText('Saya Warga')).toBeVisible({ timeout: 30_000 });
}

test('a resident joins with the RT code and sees the active task', async ({
  app,
  screen,
}) => {
  await openTaskList(app, screen, 'Sari');

  // The list shows the seeded campaign by its template title.
  await expect(screen.getByText(TASK_ROW)).toBeVisible({ timeout: 30_000 });

  await signOut(app, screen);
});

test(
  'the synchronized task and its safety instruction stay readable offline',
  { platforms: ['android'] },
  async ({ app, screen, device }) => {
    // 1. Synchronize while online.
    await openTaskList(app, screen, 'Budi');

    // 2. Open the task so its detail is cached locally.
    await screen.getByText(TASK_ROW).first().tap();
    await expect(screen.getByText(SAFETY_TEXT)).toBeVisible({
      timeout: 30_000,
    });

    // 3. Cut the network and restart. The stored session is restored when the
    // resident entry screen opens, which is the app's real offline path.
    await device.setAirplaneMode(true);
    try {
      await app.restart();
      await screen.getByText('Saya Warga').tap();

      // 4. The restored session states it is offline and unverified — never
      // presented as live.
      await expect(
        screen.getByText(
          /Mode offline\. Sesi dan informasi tugas tersimpan belum diverifikasi ulang/,
        ),
      ).toBeVisible({ timeout: 30_000 });

      // 5. The cached task is still reachable.
      await screen.getByText('Lihat Tugas Kesiapsiagaan').tap();
      await expect(screen.getByText(TASK_ROW)).toBeVisible({
        timeout: 30_000,
      });

      // 6. The list says the data is cached rather than live. The banner is one
      // node with the sync time and caveat appended, so match a substring.
      await expect(
        screen.getByText(
          /Mode offline • data tugas tersimpan, belum diperbarui/,
        ),
      ).toBeVisible();

      // 7. The locked safety instruction is still readable offline.
      await screen.getByText(TASK_ROW).first().tap();
      await expect(screen.getByText(SAFETY_TEXT)).toBeVisible({
        timeout: 30_000,
      });
    } finally {
      await device.setAirplaneMode(false);
    }

    // Signing out needs the network, so it runs after airplane mode is off.
    await signOut(app, screen);
  },
);

test(
  'the voluntary decline action stays available offline, with no penalty wording',
  { platforms: ['android'] },
  async ({ app, screen, device }) => {
    await openTaskList(app, screen, 'Raka');

    await device.setAirplaneMode(true);
    try {
      // Open the detail while offline: the task and both choices stay usable.
      await screen.getByText(TASK_ROW).first().tap();

      // INV-03: declining must remain possible and must not be framed as a
      // penalty. Both actions stay on screen with no network.
      await expect(screen.getByText('Tidak Ikut')).toBeVisible();
      await expect(screen.getByText('Saya Ikut')).toBeVisible();
      await expect(
        screen.getByText(/Ikut atau tidak ikut adalah pilihan Anda/),
      ).toBeVisible();
    } finally {
      await device.setAirplaneMode(false);
    }

    await signOut(app, screen);
  },
);
