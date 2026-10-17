import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

// AT-007 / O-01: the Darurat route must open with no network, and an absent
// directory must never be presented as current data.

test('role selection exposes both roles and the Darurat entry', async ({
  app,
  screen,
}) => {
  await app.open();

  await expect(
    screen.getByText('Kesiapsiagaan banjir bersama warga'),
  ).toBeVisible();
  await expect(
    screen.getByText('Saya Ketua RT/RW atau Pendamping'),
  ).toBeVisible();
  await expect(screen.getByText('Saya Warga')).toBeVisible();
  await expect(screen.getByText('Darurat')).toBeVisible();
});

test(
  'Darurat opens with the network off and states its own status',
  { platforms: ['android'] },
  async ({ app, screen, device }) => {
    await device.setAirplaneMode(true);
    try {
      await app.open();
      await screen.getByText('Darurat').tap();

      await expect(screen.getByText('Informasi Darurat')).toBeVisible();
      // The status card reports offline mode...
      await expect(
        screen.getByText('Mode offline • menampilkan direktori yang tersimpan di perangkat.'),
      ).toBeVisible();
      // ...and, with nothing cached, the body says so instead of inventing a
      // directory. Never a fabricated contact list.
      await expect(
        screen.getByText(
          /Belum ada direktori darurat tersimpan|Informasi darurat belum dapat dimuat|Direktori belum tersedia pada perangkat ini/,
        ),
      ).toBeVisible();
      await expect(screen.getByText('Kontak Darurat')).toBeHidden();
    } finally {
      await device.setAirplaneMode(false);
    }
  },
);
