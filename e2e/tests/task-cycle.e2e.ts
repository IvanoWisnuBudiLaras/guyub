import { test } from '@e2e-dev/mobile';
import { expect, type App, type Screen } from 'e2e';

// The full task cycle through the real app: a resident joins and submits a
// completion, and an operator verifies it. This is the boundary the unit and
// emulator suites cannot reach — they assert that the service keeps completion
// pending, never that the app can drive both roles to that state and back.
//
// AT-005: a resident's submission is not official completion. It stays
// "Menunggu Verifikasi RT" until an authorized operator verifies it, and only
// then does the resident see it as verified.
//
// The RT, template, campaign, and operator account are seeded before the run by
// functions/test/seed_e2e_campaign.js, through the real callables.
//
// Locators use visible text and substrings: Flutter widget `Key`s are not
// exposed to the driver, and several screens render a label plus its detail
// inside one accessibility node.

const JOIN_CODE = 'GUYUBE2E2026';
const OPERATOR_EMAIL = 'operator@guyub.test';
const OPERATOR_PASSWORD = 'test-password-123';
const TASK_TITLE = 'Persiapan rumah tangga';
const TASK_ROW = new RegExp(TASK_TITLE);

// Both entry screens restore a stored session asynchronously when they open, so
// they briefly show their form and then navigate on. Let that settle before
// deciding which screen is actually there.
const RESTORE_SETTLE_MS = 5_000;

async function enterAsResident(
  app: App,
  screen: Screen,
  nickname: string,
) {
  await app.open();

  if (await screen.getByText('Saya Warga').isVisible()) {
    await screen.getByText('Saya Warga').tap();
  }
  await new Promise((resolve) => setTimeout(resolve, RESTORE_SETTLE_MS));

  // A restored session lands on the home screen; the task list is one tap on.
  if (await screen.getByText('Lihat Tugas Kesiapsiagaan').isVisible()) {
    await screen.getByText('Lihat Tugas Kesiapsiagaan').tap();
    return;
  }

  await expect(screen.getByPlaceholder('Kode RT')).toBeVisible({
    timeout: 30_000,
  });
  await screen.getByPlaceholder('Kode RT').fill(JOIN_CODE);
  await screen.getByPlaceholder('Nama panggilan').fill(nickname);
  await screen.getByText('Masuk ke RT').tap();
  await screen.getByText('Lihat Tugas Kesiapsiagaan').tap();
}

async function enterAsOperator(
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

// This test drives two roles in sequence — a resident enrollment and completion,
// then an operator sign-in and verification — so it needs more than the default
// per-test budget.
test(
  'a resident submission stays pending until the operator verifies it',
  { timeout: 300_000 },
  async ({ app, screen }) => {
  // 1. Resident joins and completes the task. The note is left empty: a note
  //    would be sent, but the no-note path is the one the offline outbox also
  //    uses, so it is the one worth driving here.
  await enterAsResident(app, screen, 'Sari');
  await expect(screen.getByText(TASK_ROW)).toBeVisible({ timeout: 30_000 });

  await screen.getByText(TASK_ROW).first().tap();
  await screen.getByText('Saya Ikut').tap();

  // Joining makes the completion form available. Its intro text, the optional
  // photo notice, and the note label all render inside the note field's
  // accessibility node as a placeholder, which `getByText` does not read, so
  // the assertion is on the submit action — present only after joining.
  await expect(
    screen.getByText('Kirim untuk Verifikasi RT'),
  ).toBeVisible({ timeout: 30_000 });
  await screen.getByText('Kirim untuk Verifikasi RT').tap();

  // AT-005: the resident's own view says pending, never complete.
  await expect(
    screen.getByText(/Menunggu Verifikasi RT/),
  ).toBeVisible({ timeout: 30_000 });

  // 2. Operator verifies it. The pending item is scoped to the same RT.
  await enterAsOperator(app, screen);
  await screen.getByText('Tinjau Penyelesaian Warga').tap();

  await expect(screen.getByText('Verifikasi Tugas')).toBeVisible({
    timeout: 30_000,
  });
  await expect(screen.getByText(/Dikirim oleh Sari/)).toBeVisible({
    timeout: 30_000,
  });
  await expect(screen.getByText(/Status: Menunggu Verifikasi RT/)).toBeVisible();

  await screen.getByText('Tinjau dan Verifikasi').tap();

  // Verification is a deliberate, confirmed action, not a single tap.
  await expect(screen.getByText('Verifikasi penyelesaian?')).toBeVisible({
    timeout: 30_000,
  });
  await screen.getByText('Verifikasi').tap();

  // The queue drains, which is the durable evidence that the transition
  // happened. The success snackbar is transient and can disappear before an
  // assertion sees it, so it is not what this test relies on.
  await expect(
    screen.getByText(/Belum ada penyelesaian yang menunggu verifikasi RT/),
  ).toBeVisible({ timeout: 30_000 });
  await expect(screen.getByText(/Dikirim oleh Sari/)).not.toBeVisible();
  },
);
