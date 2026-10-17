/// A backend callable failure, normalised across transports.
///
/// [code] keeps the gRPC status name (`permission-denied`, `unavailable`, …)
/// because boundary classes match on those strings for offline and retry
/// handling. A new transport must preserve them.
final class CallableException implements Exception {
  const CallableException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CallableException($code): $message';
}

/// Invokes a backend callable by name.
///
/// Implemented by the Firebase SDK transport and by the plain-HTTP transport,
/// so boundary classes do not care which runtime serves the backend.
abstract interface class CallableClient {
  Future<Object?> call(String name, Map<String, Object?> data);
}
