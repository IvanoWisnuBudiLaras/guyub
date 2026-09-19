import 'app/bootstrap.dart';
import 'core/config/app_config.dart';

/// Titik masuk default aplikasi Guyub.id.
///
/// Membaca opsi environment dari flag `--dart-define=ENV=...` saat kompilasi/run.
/// Default ke [AppConfig.development] jika parameter tidak diberikan.
void main() async {
  const envRaw = String.fromEnvironment('ENV', defaultValue: 'development');
  final config = switch (envRaw.toLowerCase()) {
    'prod' || 'production' => AppConfig.production(),
    'test' => AppConfig.test(),
    _ => AppConfig.development(),
  };

  await bootstrap(config);
}
