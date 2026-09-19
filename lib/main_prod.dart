import 'app/bootstrap.dart';
import 'core/config/app_config.dart';

/// Titik masuk eksplisit untuk mode Produksi (Production).
///
/// Menggunakan konfigurasi backend rilis tanpa emulator.
void main() async {
  await bootstrap(AppConfig.production());
}
