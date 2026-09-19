import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/app/bootstrap.dart';
import 'package:guyub/core/config/app_config.dart';

void main() {
  setUp(() {
    AppConfig.resetForTesting();
  });

  test('createBootstrapApp menginisialisasi konfigurasi test tanpa akses backend produksi', () async {
    final testConfig = AppConfig.test();

    final widget = await createBootstrapApp(testConfig);

    expect(widget, isA<Widget>());
    expect(AppConfig.current.environment.isTest, isTrue);
    expect(AppConfig.current.useEmulator, isTrue);
  });
}
