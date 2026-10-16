import '../../../core/network/callable_client.dart';

import '../application/resident_session.dart';
import '../application/resident_session_boundary.dart';

/// Callable Functions adapter. Protected resident collections are never written by the client.
final class FirebaseResidentSessionBoundary implements ResidentSessionBoundary {
  const FirebaseResidentSessionBoundary(this.client);

  final CallableClient client;

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    final Object? result;
    try {
      result = await client.call('createResidentSession', {
        'joinCode': joinCode,
        'nickname': nickname,
        'requestId': requestId,
      });
    } on CallableException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'invalid-argument') {
        throw const ResidentSessionEnrollmentRejectedException();
      }
      rethrow;
    }
    final data = _map(result);
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
      final result = await client.call('validateResidentSession', {
        'sessionToken': sessionToken,
      });
      return _session(_map(result));
    } on CallableException catch (error) {
      if (error.code == 'permission-denied' ||
          error.code == 'unauthenticated' ||
          error.code == 'not-found') {
        throw const ResidentSessionInvalidException();
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw const ResidentSessionUnavailableException();
      }
      rethrow;
    }
  }

  @override
  Future<void> revokeSession(String sessionToken) async {
    await client.call('revokeResidentSession', {'sessionToken': sessionToken});
  }

  @override
  Future<void> deleteOwnResidentData({
    required String sessionToken,
    required String residentId,
    required String communityId,
  }) async {
    final result = await client.call('deleteOwnResidentData', {
      'sessionToken': sessionToken,
      'residentId': residentId,
      'communityId': communityId,
    });
    final data = _map(result);
    if (data['deleted'] != true) {
      throw const FormatException('Backend has not confirmed data deletion.');
    }
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
