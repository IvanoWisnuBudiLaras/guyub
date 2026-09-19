import 'app/bootstrap.dart';
import 'core/config/app_config.dart';

/// Titik masuk eksplisit untuk mode Pengembangan (Development).
///
/// Menggunakan konfigurasi lokal dengan Firebase emulator.
void main() async {
  await bootstrap(AppConfig.development());
}
