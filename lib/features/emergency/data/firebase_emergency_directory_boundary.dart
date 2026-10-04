import 'package:cloud_functions/cloud_functions.dart';

import '../application/emergency_directory.dart';
import '../application/emergency_directory_boundary.dart';

/// Callable-only adapter. Emergency directory data is never read from Firestore.
final class FirebaseEmergencyDirectoryBoundary
    implements EmergencyDirectoryBoundary {
  const FirebaseEmergencyDirectoryBoundary(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) async {
    final result = await functions.httpsCallable('getEmergencyDirectory').call(
      <String, Object?>{'sessionToken': sessionToken},
    );
    return EmergencyDirectoryResponse.fromWire(result.data);
  }
}
