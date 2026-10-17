import { test } from '@e2e-dev/mobile';
import { expect, type App, type Screen } from 'e2e';

// Voluntary helper opt-in through the real app.
//
// AT-020 / INV-03: helping is opt-in, private, and voluntary. The resident must
// confirm their own choice without pressure, and the RT can only send requests
// after that consent exists. Nothing about this may read as a penalty for
// declining.
//
// The RT, template, campaign, and operator account are seeded before the run by
// functions/test/seed_e2e_campaign.js, through the real callables.

const JOIN_CODE = 'GUYUBE2E2026';

// The entry screen restores a stored session asynchronously when it opens, so
// it briefly shows its form and then navigates on.
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

  if (!(await screen.getByText('Kesediaan Membantu').isVisible())) {
    await expect(screen.getByPlaceholder('Kode RT')).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByPlaceholder('Kode RT').fill(JOIN_CODE);
    await screen.getByPlaceholder('Nama panggilan').fill(nickname);
    await screen.getByText('Masuk ke RT').tap();
  }

  await expect(screen.getByText('Kesediaan Membantu')).toBeVisible({
    timeout: 30_000,
  });
}

test(
  'helper willingness requires the resident to confirm their own choice',
  { timeout: 300_000 },
  async ({ app, screen }) => {
    await enterAsResident(app, screen, 'Sari');
    await screen.getByText('Kesediaan Membantu').tap();

    await expect(screen.getByText('Kesediaan Membantu')).toBeVisible({
      timeout: 30_000,
    });

    // The screen states the boundary before anything is chosen: helping is
    // voluntary, declining carries no penalty, and the RT can only send a
    // request once the resident agrees.
    // The screen loads the resident's volunteer data first, so the content
    // arrives after the header. Wait for it rather than asserting immediately.
    await expect(
      screen.getByText(/Menjadi relawan sepenuhnya sukarela/),
    ).toBeVisible({ timeout: 30_000 });
    await expect(
      screen.getByText(/menolak setiap permintaan atau mengundurkan diri tanpa penalti/),
    ).toBeVisible();
    await expect(
      screen.getByText(/RT hanya dapat mengirim permintaan setelah Anda setuju/),
    ).toBeVisible();

    // The opt-in is a switch whose accessible name carries the label and its
    // subtitle together.
    // Turning it on does not save anything by itself — a separate, explicit
    // consent confirmation appears and must be ticked.
    await screen
      .getByText(/Saya bersedia membantu secara sukarela/)
      .tap();
    await expect(
      screen.getByText('Saya mengonfirmasi pilihan ini tanpa tekanan.'),
    ).toBeVisible({ timeout: 30_000 });
    await expect(screen.getByText('Simpan kesediaan')).toBeVisible();

    // Saving without ticking the confirmation must not be possible. The button
    // is present but disabled, so tapping it changes nothing: the consent
    // checkbox and the save action are still on screen afterwards.
    await screen.getByText('Simpan kesediaan').tap();
    await expect(
      screen.getByText('Saya mengonfirmasi pilihan ini tanpa tekanan.'),
    ).toBeVisible();
    await expect(screen.getByText('Simpan kesediaan')).toBeVisible();

    // With the confirmation ticked, the choice saves.
    await screen.getByText('Saya mengonfirmasi pilihan ini tanpa tekanan.').tap();
    await screen.getByText('Simpan kesediaan').tap();

    // The saved state is reflected by the switch itself: after saving, the
    // screen reloads and the pending form collapses, leaving the switch on.
    // The switch keeps its combined accessible name, so it is matched as a
    // substring, and withdrawal remains available by turning it back off.
    await expect(
      screen.getByText(/Saya bersedia membantu secara sukarela/),
    ).toBeVisible({ timeout: 30_000 });
    await expect(
      screen.getByText('Saya mengonfirmasi pilihan ini tanpa tekanan.'),
    ).not.toBeVisible();
  },
);
