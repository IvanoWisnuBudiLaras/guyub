import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'core/config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap(AppConfig.development());
}