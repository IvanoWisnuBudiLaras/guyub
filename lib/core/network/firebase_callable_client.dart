import 'package:cloud_functions/cloud_functions.dart';

import 'callable_client.dart';

/// Firebase Functions transport. Behaviour is identical to calling
/// `FirebaseFunctions.httpsCallable` directly, which is what the boundaries
/// did before this seam existed.
final class FirebaseCallableClient implements CallableClient {
  const FirebaseCallableClient(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<Object?> call(String name, Map<String, Object?> data) async {
    try {
      final result = await functions.httpsCallable(name).call(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw CallableException(error.code, error.message ?? '');
    }
  }
}
