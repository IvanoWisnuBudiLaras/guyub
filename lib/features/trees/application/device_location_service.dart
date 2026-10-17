import 'dart:async';

import '../domain/tree_point.dart';

/// Kontrak layanan sensor GPS perangkat untuk penanaman pohon.
abstract interface class DeviceLocationService {
  /// Memeriksa apakah izin lokasi telah diberikan.
  Future<bool> hasPermission();

  /// Meminta izin lokasi runtime kepada pengguna.
  Future<bool> requestPermission();

  /// Memperoleh pembacaan GPS terkini dari perangkat.
  Future<DeviceGpsReading> getCurrentReading();
}

/// Implementasi tiruan DeviceLocationService untuk pengujian dan emulator.
final class MockDeviceLocationService implements DeviceLocationService {
  MockDeviceLocationService({
    this.hasPermissionResult = true,
    this.requestPermissionResult = true,
    DeviceGpsReading? defaultReading,
  }) : _reading =
           defaultReading ??
           DeviceGpsReading(
             latitude: -8.065432,
             longitude: 111.901234,
             accuracyMeters: 12.0,
             isMocked: false,
             timestamp: DateTime.now(),
           );

  bool hasPermissionResult;
  bool requestPermissionResult;
  DeviceGpsReading _reading;

  void setReading(DeviceGpsReading reading) {
    _reading = reading;
  }

  @override
  Future<bool> hasPermission() async => hasPermissionResult;

  @override
  Future<bool> requestPermission() async => requestPermissionResult;

  @override
  Future<DeviceGpsReading> getCurrentReading() async => _reading;
}
