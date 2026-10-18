import { test } from '@e2e-dev/mobile';
import { expect, type App, type Screen } from 'e2e';

// RT-owned history through the real app: an operator sees the RT's tasks, their
// status, and the lifecycle events the server recorded — then closes an active
// task and watches history reflect it.
//
// AT-015: preparedness history belongs to the RT, not to an operator account,
// and the lifecycle timeline exposes event types and timestamps only. Closing a
// task is audited and never implies completion verification.
//
// The RT, template, and ACTIVE campaign are seeded before the run by
// functions/test/seed_e2e_campaign.js, through the real callables.
//
// Locators use visible text and substrings: Flutter widget `Key`s are not
// exposed to the driver, and several screens render a label plus its value
// inside one accessibility node.

const OPERATOR_EMAIL = 'operator@guyub.test';
const OPERATOR_PASSWORD = 'test-password-123';
const TASK_TITLE = 'Persiapan rumah tangga';
const TASK_ROW = new RegExp(TASK_TITLE);

// The operator login screen restores a stored session asynchronously when it
// opens, so it briefly shows the form and then navigates on. Let that settle
// before deciding which screen is actually there.
const RESTORE_SETTLE_MS = 5_000;

async function signInOperator(
  app: App,
  screen: Screen,
) {
  await app.open();

  await expect(
    screen.getByText('Saya Ketua RT/RW atau Pendamping'),
  ).toBeVisible({ timeout: 30_000 });
  await screen.getByText('Saya Ketua RT/RW atau Pendamping').tap();

  await new Promise((resolve) => setTimeout(resolve, RESTORE_SETTLE_MS));
  if (await screen.getByText('Ruang Operator').isVisible()) return;

  await expect(screen.getByPlaceholder('Email')).toBeVisible({
    timeout: 30_000,
  });
  await screen.getByPlaceholder('Email').fill(OPERATOR_EMAIL);
  await screen.getByPlaceholder('Kata sandi').fill(OPERATOR_PASSWORD);
  await screen.getByText('Masuk').tap();

  await expect(screen.getByText('Ruang Operator')).toBeVisible({
    timeout: 30_000,
  });
}

// Returns to the operator home from any operator screen. Uses the in-app Back
// control rather than `app.open()`: reopening the app lands on role selection
// and drops the operator session, so the home screen would never appear.
async function goToOperatorHome(screen: Screen) {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (await screen.getByText('Ruang Operator').isVisible()) return;
    if (await screen.getByText('Back').isVisible()) {
      await screen.getByText('Back').tap();
      continue;
    }
    break;
  }
  await expect(screen.getByText('Ruang Operator')).toBeVisible({
    timeout: 30_000,
  });
}

test(
  'RT history lists the task and records an explicit close',
  { timeout: 300_000 },
  async ({ app, screen }) => {
    await signInOperator(app, screen);

    // 1. History lists the seeded campaign with its server-recorded status.
    await screen.getByText('Lihat Riwayat Tugas RT').tap();
    await expect(screen.getByText('Riwayat Tugas RT')).toBeVisible({
      timeout: 30_000,
    });
    await expect(screen.getByText(TASK_ROW)).toBeVisible({ timeout: 30_000 });
    await expect(screen.getByText(/Status: Aktif/)).toBeVisible();
    // The immutable template version travels with the history entry, so a later
    // template edit cannot rewrite what was activated.
    await expect(screen.getByText(/Versi template: 1/)).toBeVisible();

    // 2. Close it from the active list — closing lives there, not in history.
    await goToOperatorHome(screen);
    await screen.getByText('Tinjau Tugas Aktif').tap();
    await expect(screen.getByText('Tugas Aktif RT')).toBeVisible({
      timeout: 30_000,
    });

    await screen.getByText('Tutup tugas aktif').first().tap();

    // Closing is a deliberate, confirmed action.
    await expect(screen.getByText('Tutup tugas aktif?')).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByText('Tutup tugas').tap();

    // 3. History now reports the close, and the timeline records it. Only the
    //    event type and time are exposed — no operator identity, no free text.
    await goToOperatorHome(screen);
    await screen.getByText('Lihat Riwayat Tugas RT').tap();
    await expect(screen.getByText('Riwayat Tugas RT')).toBeVisible({
      timeout: 30_000,
    });
    await expect(screen.getByText(/Status: Ditutup/)).toBeVisible({
      timeout: 30_000,
    });

    await screen.getByText('Lihat riwayat perubahan').first().tap();
    await expect(screen.getByText('Perubahan yang dicatat server:')).toBeVisible({
      timeout: 30_000,
    });
    await expect(screen.getByText(/^Diaktifkan: /)).toBeVisible();
    await expect(screen.getByText(/^Ditutup: /)).toBeVisible();
  },
);
