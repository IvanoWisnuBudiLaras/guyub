import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

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
const SAFETY_TEXT = new RegExp(
  'Jangan mendekati air banjir atau instalasi listrik basah',
);

type Screen = {
  getByText: (text: string | RegExp) => {
    tap: () => Promise<void>;
    isVisible: () => Promise<boolean>;
  };
  getByPlaceholder: (text: string) => {
    fill: (value: string) => Promise<void>;
    isVisible: () => Promise<boolean>;
  };
};

async function signInOperator(
  app: { open: () => Promise<void> },
  screen: Screen,
) {
  await app.open();

  // Role selection is shown when no session was restored.
  if (await screen.getByText('Saya Ketua RT/RW atau Pendamping').isVisible()) {
    await screen.getByText('Saya Ketua RT/RW atau Pendamping').tap();
  }

  // A restored session goes straight to the home screen; only sign in when the
  // form is actually on screen.
  if (!(await screen.getByText('Ruang Operator').isVisible())) {
    await expect(screen.getByPlaceholder('Email')).toBeVisible({
      timeout: 30_000,
    });
    await screen.getByPlaceholder('Email').fill(OPERATOR_EMAIL);
    await screen.getByPlaceholder('Kata sandi').fill(OPERATOR_PASSWORD);
    await screen.getByText('Masuk').tap();
  }

  await expect(screen.getByText('Ruang Operator')).toBeVisible({
    timeout: 30_000,
  });
}

// Returns to role selection so the next test starts signed out. The operator
// flow is several screens deep, so this walks back to the home screen first —
// the sign-out control lives only there.
async function signOutOperator(
  app: { open: () => Promise<void> },
  screen: Screen,
) {
  await app.open();

  // Bounded: a restored session may land on the home screen, or deeper.
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (await screen.getByText('Saya Ketua RT/RW atau Pendamping').isVisible()) {
      return;
    }
    if (await screen.getByText('Ruang Operator').isVisible()) {
      await screen.getByText('Keluar').tap();
      break;
    }
    await screen.getByText('Back').tap();
  }

  await expect(
    screen.getByText('Saya Ketua RT/RW atau Pendamping'),
  ).toBeVisible({ timeout: 30_000 });
}

test('an operator signs in and reaches the operator home', async ({
  app,
  screen,
}) => {
  await signInOperator(app, screen);

  // The seeded membership: role label and RT scope, both server-derived.
  await expect(screen.getByText('Ketua RT/RW')).toBeVisible();
  await expect(screen.getByText(`RT ${RT_ID}`)).toBeVisible();

  await signOutOperator(app, screen);
});

test('the operator opens the reviewed safe catalog', async ({ app, screen }) => {
  await signInOperator(app, screen);

  await screen.getByText('Buka Katalog Tugas Aman').tap();

  // The seeded, reviewed template — the only kind activation accepts.
  await expect(screen.getByText('Katalog Tugas Aman')).toBeVisible({
    timeout: 30_000,
  });
  await expect(screen.getByText(TEMPLATE_TITLE)).toBeVisible({
    timeout: 30_000,
  });

  // Its locked instructions render in the catalog, before any draft exists.
  await expect(screen.getByText(SAFETY_TEXT)).toBeVisible();

  await signOutOperator(app, screen);
});
