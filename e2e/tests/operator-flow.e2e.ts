import { test } from '@e2e-dev/mobile';
import { expect, type App, type Screen } from 'e2e';

// The operator journey through the real app: sign in with Firebase Auth,
// land on the operator home, and open the reviewed safe catalog.
//
// This is the layer the unit and emulator suites cannot cover: they assert on
// services and boundaries, never on whether the app can actually sign a human
// in and render what came back.
//
// The RT, template, campaign, and operator account are seeded before the run by
// functions/test/seed_e2e_campaign.js, through the real callables.
//
// Locators use visible text: Flutter widget `Key`s are not exposed to the
// driver, and several screens render a label plus its detail inside one
// accessibility node, so substrings are used where a node joins lines.

const OPERATOR_EMAIL = 'operator@guyub.test';
const OPERATOR_PASSWORD = 'test-password-123';
const RT_ID = 'rt-e2e';
const TEMPLATE_TITLE = 'Persiapan rumah tangga';
// The catalog card renders the title twice in one accessibility node, joined
// with the version line, so an exact match misses.
const TEMPLATE_ROW = new RegExp(TEMPLATE_TITLE);
const SAFETY_TEXT = new RegExp(
  'Jangan mendekati air banjir atau instalasi listrik basah',
);

async function signInOperator(
  app: App,
  screen: Screen,
) {
  await app.open();

  await expect(
    screen.getByText('Saya Ketua RT/RW atau Pendamping'),
  ).toBeVisible({ timeout: 30_000 });
  await screen.getByText('Saya Ketua RT/RW atau Pendamping').tap();

  // The login screen restores a stored session asynchronously when it opens, so
  // it can briefly show the form and then navigate to the home screen. Let the
  // restore settle before deciding which screen we are on — otherwise the fill
  // below races against that navigation and fails.
  await new Promise((resolve) => setTimeout(resolve, 5_000));
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

test('an operator signs in and reaches the operator home', async ({
  app,
  screen,
}) => {
  await signInOperator(app, screen);

  // The seeded membership: role label and RT scope, both server-derived.
  await expect(screen.getByText('Ketua RT/RW')).toBeVisible();
  await expect(screen.getByText(`RT ${RT_ID}`)).toBeVisible();

});

test('the operator opens the reviewed safe catalog', async ({ app, screen }) => {
  await signInOperator(app, screen);

  await screen.getByText('Buka Katalog Tugas Aman').tap();

  // The seeded, reviewed template — the only kind activation accepts.
  await expect(screen.getByText('Katalog Tugas Aman')).toBeVisible({
    timeout: 30_000,
  });
  await expect(screen.getByText(TEMPLATE_ROW)).toBeVisible({
    timeout: 30_000,
  });

  // Its locked instructions render in the catalog, before any draft exists.
  await expect(screen.getByText(SAFETY_TEXT)).toBeVisible();

});

test(
  'the draft shows the locked instructions and only offers the allowed slots',
  async ({ app, screen }) => {
    await signInOperator(app, screen);
    await screen.getByText('Buka Katalog Tugas Aman').tap();
    await expect(screen.getByText(TEMPLATE_ROW)).toBeVisible({
      timeout: 30_000,
    });

    await screen.getByText('Pilih template').tap();

    // AT-003: the core and safety instructions come from the reviewed template
    // and are shown locked — the operator cannot author them. The card renders
    // its heading, both instructions, and the KESELAMATAN label inside a single
    // accessibility node, so each is matched as a substring.
    await expect(screen.getByText('Siapkan Draf Tugas')).toBeVisible({
      timeout: 30_000,
    });
    await expect(
      screen.getByText(/Instruksi template terkunci/),
    ).toBeVisible();
    await expect(screen.getByText(SAFETY_TEXT)).toBeVisible();
    await expect(
      screen.getByText(/Simpan dokumen penting di wadah yang mudah dijangkau/),
    ).toBeVisible();
    await expect(screen.getByText(/KESELAMATAN/)).toBeVisible();

    // The only operator-editable fields are the two safe slots. There is no
    // free-text instruction or address input anywhere on the screen.
    await expect(screen.getByText('Bagian yang dapat diatur')).toBeVisible();
    await expect(screen.getByText('Pilih batas waktu')).toBeVisible();
    await expect(
      screen.getByText('Jenis lokasi umum (opsional)'),
    ).toBeVisible();

    // A draft cannot be created before a deadline is chosen: the deadline is
    // the one slot the server requires.
    await screen.getByText('Lanjut ke konfirmasi').tap();
    await expect(
      screen.getByText('Pilih batas waktu di masa depan.'),
    ).toBeVisible({ timeout: 30_000 });
  },
);

test(
  'a draft is not active until the operator explicitly confirms it',
  async ({ app, screen }) => {
    await signInOperator(app, screen);
    await screen.getByText('Buka Katalog Tugas Aman').tap();
    await expect(screen.getByText(TEMPLATE_ROW)).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByText('Pilih template').tap();
    await expect(screen.getByText('Siapkan Draf Tugas')).toBeVisible({
      timeout: 30_000,
    });

    // Fill the one required slot. The Material pickers open on a valid default
    // (today, one hour ahead), so accepting them as-is yields a future deadline.
    await screen.getByText('Pilih batas waktu').tap();
    await screen.getByText('OK').tap();
    await screen.getByText('OK').tap();

    await screen.getByText('Lanjut ke konfirmasi').tap();

    // The confirmation screen is the human checkpoint before distribution.
    await expect(screen.getByText('Konfirmasi Aktivasi Tugas')).toBeVisible({
      timeout: 30_000,
    });
    // AT-001: creating a draft never activates or distributes anything.
    await expect(
      screen.getByText('Draf belum aktif dan belum dibagikan.'),
    ).toBeVisible();
    // The locked instructions are restated at the point of decision.
    await expect(screen.getByText(SAFETY_TEXT)).toBeVisible();

    // AT-016: the WhatsApp summary is copy-only and active-only, so a draft
    // must not offer it at all.
    await expect(
      screen.getByText('Salin teks untuk WhatsApp'),
    ).not.toBeVisible();

    // Activation is an explicit, separate operator action.
    await screen.getByText('Konfirmasi dan aktifkan').tap();
    await expect(screen.getByText('Tugas aktif untuk RT ini.')).toBeVisible({
      timeout: 30_000,
    });

    // Only now does the copy-only distribution path appear.
    await expect(
      screen.getByText('Salin teks untuk WhatsApp'),
    ).toBeVisible();
  },
);
