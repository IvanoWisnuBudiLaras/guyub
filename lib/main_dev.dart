import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'core/config/app_config.dart';

/// Titik masuk eksplisit untuk mode Pengembangan (Development).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap(AppConfig.development());
}
