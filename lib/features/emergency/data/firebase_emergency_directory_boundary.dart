import '../../../core/network/callable_client.dart';

import '../application/emergency_directory.dart';
import '../application/emergency_directory_boundary.dart';

/// Callable-only adapter. Emergency directory data is never read from Firestore.
final class FirebaseEmergencyDirectoryBoundary
    implements EmergencyDirectoryBoundary {
  const FirebaseEmergencyDirectoryBoundary(this.client);

  final CallableClient client;

  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) async {
    final result = await client.call('getEmergencyDirectory', <String, Object?>{
      'sessionToken': sessionToken,
    });
    return EmergencyDirectoryResponse.fromWire(result);
  }
}
