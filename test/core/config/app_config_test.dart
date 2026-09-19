import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/config/app_config.dart';
import 'package:guyub/core/config/app_environment.dart';

void main() {
  setUp(() {
    AppConfig.resetForTesting();
  });

  group('AppEnvironment', () {
    test('melakukan parsing nama environment dengan benar', () {
      expect(
        AppEnvironment.fromString('development'),
        AppEnvironment.development,
      );
      expect(AppEnvironment.fromString('dev'), AppEnvironment.development);
      expect(AppEnvironment.fromString('test'), AppEnvironment.test);
      expect(AppEnvironment.fromString('testing'), AppEnvironment.test);
      expect(
        AppEnvironment.fromString('production'),
        AppEnvironment.production,
      );
      expect(AppEnvironment.fromString('prod'), AppEnvironment.production);
      expect(AppEnvironment.fromString('invalid'), AppEnvironment.development);
      expect(AppEnvironment.fromString(null), AppEnvironment.development);
    });

    test('flags helper isDevelopment, isTest, isProduction bekerja akurat', () {
      expect(AppEnvironment.development.isDevelopment, isTrue);
      expect(AppEnvironment.development.isTest, isFalse);
      expect(AppEnvironment.development.isProduction, isFalse);

      expect(AppEnvironment.test.isTest, isTrue);
      expect(AppEnvironment.test.isDevelopment, isFalse);

      expect(AppEnvironment.production.isProduction, isTrue);
      expect(AppEnvironment.production.isDevelopment, isFalse);
    });
  });

  group('AppConfig', () {
    test('factory development mengaktifkan emulator secara default', () {
      final config = AppConfig.development();
      expect(config.environment, AppEnvironment.development);
      expect(config.appName, contains('DEV'));
      expect(config.useEmulator, isTrue);
      expect(config.firestorePort, 8080);
      expect(config.authPort, 9099);
    });

    test('factory test menggunakan mode emulator terisolasi', () {
      final config = AppConfig.test();
      expect(config.environment, AppEnvironment.test);
      expect(config.appName, contains('TEST'));
      expect(config.useEmulator, isTrue);
      expect(config.emulatorHost, '127.0.0.1');
    });

    test('factory production menonaktifkan emulator', () {
      final config = AppConfig.production();
      expect(config.environment, AppEnvironment.production);
      expect(config.appName, 'Guyub');
      expect(config.useEmulator, isFalse);
    });

    test('initialize dan resetForTesting memelihara isolasi konfigurasi', () {
      expect(AppConfig.current.environment, AppEnvironment.development);

      AppConfig.initialize(AppConfig.production());
      expect(AppConfig.current.environment, AppEnvironment.production);

      AppConfig.resetForTesting();
      expect(AppConfig.current.environment, AppEnvironment.development);
    });
  });
}
