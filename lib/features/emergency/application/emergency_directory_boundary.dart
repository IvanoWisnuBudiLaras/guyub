import 'emergency_directory.dart';

/// Callable-only read boundary for the configured emergency directory.
abstract interface class EmergencyDirectoryBoundary {
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  });
}
