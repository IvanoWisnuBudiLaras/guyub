import 'package:cloud_functions/cloud_functions.dart';

import '../application/resident_session.dart';
import '../application/resident_session_boundary.dart';

/// Callable Functions adapter. Protected resident collections are never written by the client.
final class FirebaseResidentSessionBoundary implements ResidentSessionBoundary {
  const FirebaseResidentSessionBoundary(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    late final HttpsCallableResult<dynamic> result;
    try {
      result = await functions.httpsCallable('createResidentSession').call({
        'joinCode': joinCode,
        'nickname': nickname,
        'requestId': requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'invalid-argument') {
        throw const ResidentSessionEnrollmentRejectedException();
      }
      rethrow;
    }
    final data = _map(result.data);
    final token = data['sessionToken'];
    if (token is! String || token.isEmpty) {
      throw const FormatException(
        'Backend returned an invalid resident token.',
      );
    }
    return ResidentSessionGrant(sessionToken: token, session: _session(data));
  }

  @override
  Future<ResidentSession> validateSession(String sessionToken) async {
    try {
      final result = await functions
          .httpsCallable('validateResidentSession')
          .call({'sessionToken': sessionToken});
      return _session(_map(result.data));
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated' ||
          error.code == 'not-found') {
        throw const ResidentSessionInvalidException();
      }
      rethrow;
    }
  }

  @override
  Future<void> revokeSession(String sessionToken) async {
    await functions.httpsCallable('revokeResidentSession').call({
      'sessionToken': sessionToken,
    });
  }

  ResidentSession _session(Map<String, Object?> data) {
    final expiresAt = _date(data['expiresAt']);
    final requiredFields = [
      data['residentId'],
      data['communityId'],
      data['communityName'],
      data['rtLabel'],
      data['nickname'],
    ];
    if (expiresAt == null ||
        requiredFields.any((field) => field is! String || field.isEmpty)) {
      throw const FormatException(
        'Backend returned an invalid resident session.',
      );
    }
    return ResidentSession(
      residentId: data['residentId']! as String,
      communityId: data['communityId']! as String,
      communityName: data['communityName']! as String,
      rtLabel: data['rtLabel']! as String,
      nickname: data['nickname']! as String,
      expiresAt: expiresAt,
    );
  }

  Map<String, Object?> _map(Object? data) {
    if (data is! Map) {
      throw const FormatException('Backend response is invalid.');
    }
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is Map && value['seconds'] is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (value['seconds'] as num).toInt() * 1000,
        isUtc: true,
      );
    }
    return null;
  }
}
