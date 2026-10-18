import { test } from '@e2e-dev/mobile';
import { expect, type App, type Screen } from 'e2e';

// The resident proposal path through the real app: a resident proposes a
// preparation idea, and an operator reviews it.
//
// This is the boundary the unit and emulator suites cannot reach. They assert
// that a proposal never becomes an active task directly; they cannot show that
// the app presents a proposal as inert, in the resident's own words, and then
// hands it to an operator as review context only.
//
// AT-012 / INV-08: a proposal can never become an active task on its own. The
// resident is told explicitly that nothing was activated or distributed, and
// the operator sees the proposal as something to review, with the safe-template
// mapping as a separate, deliberate action.
//
// The RT, template, campaign, and operator account are seeded before the run by
// functions/test/seed_e2e_campaign.js, through the real callables.

const JOIN_CODE = 'GUYUBE2E2026';
const OPERATOR_EMAIL = 'operator@guyub.test';
const OPERATOR_PASSWORD = 'test-password-123';
// Deliberately an ordinary household suggestion: the hazardous-text path is
// covered by the Functions emulator suites, and driving it here would prove the
// same thing twice.
const PROPOSAL_TITLE = 'Periksa saluran air bersama';
const PROPOSAL_DESCRIPTION =
  'Sebaiknya kita memeriksa saluran air di sekitar gang sebelum musim hujan.';

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

  // A restored session lands on the home screen; the enrollment form only shows
  // when there is no session.
  if (!(await screen.getByText('Usulkan Persiapan Warga').isVisible())) {
    await expect(screen.getByPlaceholder('Kode RT')).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByPlaceholder('Kode RT').fill(JOIN_CODE);
    await screen.getByPlaceholder('Nama panggilan').fill(nickname);
    await screen.getByText('Masuk ke RT').tap();
  }

  await expect(screen.getByText('Usulkan Persiapan Warga')).toBeVisible({
    timeout: 30_000,
  });
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

test(
  'a resident proposal stays inert and reaches the operator as review context',
  { timeout: 300_000 },
  async ({ app, screen }) => {
    // 1. Resident proposes a preparation idea.
    await enterAsResident(app, screen, 'Sari');
    await screen.getByText('Usulkan Persiapan Warga').tap();

    await expect(screen.getByText('Usulkan Persiapan Warga')).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByPlaceholder('Judul usulan').fill(PROPOSAL_TITLE);
    await screen.getByPlaceholder('Penjelasan singkat').fill(PROPOSAL_DESCRIPTION);
    await screen.getByText('Kirim usulan ke RT').tap();

    // INV-08: the resident is told plainly that nothing became a task. The
    // confirmation card renders its heading, that warning, and the proposal
    // title inside one accessibility node, so each is matched as a substring.
    await expect(screen.getByText(/Menunggu Tinjauan RT/)).toBeVisible({
      timeout: 30_000,
    });
    await expect(
      screen.getByText(
        /Usulan ini belum menjadi tugas\. Tidak ada tugas yang diaktifkan atau dikirim\./,
      ),
    ).toBeVisible();
    await expect(
      screen.getByText(/Usulan: Periksa saluran air bersama/),
    ).toBeVisible();

    // 2. Operator sees it in the review queue, as review context only.
    await enterAsOperator(app, screen);
    await screen.getByText('Tinjau Usulan Warga').tap();

    await expect(screen.getByText('Tinjau Usulan Warga')).toBeVisible({
      timeout: 30_000,
    });
    await expect(screen.getByText(new RegExp(PROPOSAL_TITLE))).toBeVisible({
      timeout: 30_000,
    });
    // The proposal is attributed, and its category is shown — no household
    // identity beyond the nickname the resident chose.
    await expect(screen.getByText(/Dari: Sari/)).toBeVisible();
    await expect(screen.getByText(/Kategori: Persiapan rumah tangga/)).toBeVisible();

    // The operator's options treat it as review context: map it to a reviewed
    // safe template, redirect it to official channels, or dismiss it. None of
    // these is "activate".
    await expect(
      screen.getByText('Pilih template aman untuk draf'),
    ).toBeVisible();
    await expect(screen.getByText('Arahkan ke kanal resmi')).toBeVisible();
    await expect(screen.getByText('Tutup usulan')).toBeVisible();
  },
);
