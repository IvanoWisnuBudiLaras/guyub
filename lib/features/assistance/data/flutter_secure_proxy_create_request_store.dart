import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/proxy_resident_boundary.dart';

/// Keeps an uncertain create command and its exact payload across app restarts.
/// The profile fields remain in platform-protected secure storage until the
/// backend confirms the idempotent create.
final class FlutterSecureProxyCreateRequestStore
    implements ProxyCreateRequestStore {
  FlutterSecureProxyCreateRequestStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'guyub.pending_proxy_resident_create.v1';
  static final _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
  final FlutterSecureStorage _storage;

  @override
  Future<PendingProxyResidentCreate?> read({
    required String communityId,
  }) async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.keys.toSet().difference(const {
          'communityId',
          'requestId',
          'nickname',
          'houseNumber',
          'needsAssistance',
          'residentConsentConfirmed',
        }).isNotEmpty ||
        decoded.length != 6) {
      throw const FormatException('Permintaan warga tersimpan tidak valid.');
    }
    final storedCommunityId = decoded['communityId'];
    final requestId = decoded['requestId'];
    final nickname = decoded['nickname'];
    final houseNumber = decoded['houseNumber'];
    final needsAssistance = decoded['needsAssistance'];
    final consent = decoded['residentConsentConfirmed'];
    if (storedCommunityId is! String ||
        storedCommunityId.trim().isEmpty ||
        requestId is! String ||
        !_requestIdPattern.hasMatch(requestId) ||
        nickname is! String ||
        nickname.trim().isEmpty ||
        (houseNumber != null && houseNumber is! String) ||
        needsAssistance is! bool ||
        consent is! bool) {
      throw const FormatException('Permintaan warga tersimpan tidak valid.');
    }
    if (storedCommunityId != communityId) {
      throw const ProxyCreateRequestScopeMismatch();
    }
    return PendingProxyResidentCreate(
      communityId: storedCommunityId,
      requestId: requestId,
      nickname: nickname,
      houseNumber: houseNumber as String?,
      needsAssistance: needsAssistance,
      residentConsentConfirmed: consent,
    );
  }

  @override
  Future<void> write(PendingProxyResidentCreate request) => _storage.write(
    key: _key,
    value: jsonEncode({
      'communityId': request.communityId,
      'requestId': request.requestId,
      'nickname': request.nickname,
      'houseNumber': request.houseNumber,
      'needsAssistance': request.needsAssistance,
      'residentConsentConfirmed': request.residentConsentConfirmed,
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
