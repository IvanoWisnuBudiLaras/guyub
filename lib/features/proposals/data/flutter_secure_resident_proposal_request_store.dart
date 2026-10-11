import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/resident_proposal_boundary.dart';

/// Persists only an opaque request ID and a payload hash for replay recovery.
/// The proposal text and raw resident/RT identifiers are never stored here.
final class FlutterSecureResidentProposalRequestStore
    implements ResidentProposalRequestStore {
  FlutterSecureResidentProposalRequestStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrefix = 'guyub.pending_resident_proposal.v1';
  static final _scopeHashPattern = RegExp(r'^[a-f0-9]{64}$');
  static final _requestIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
  static final _fingerprintPattern = RegExp(r'^[a-f0-9]{64}$');

  final FlutterSecureStorage _storage;

  @override
  Future<PendingResidentProposalRequest?> read({
    required String scopeHash,
  }) async {
    final raw = await _storage.read(key: _storageKey(scopeHash));
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded.keys.toSet().difference(const {
          'requestId',
          'payloadFingerprint',
        }).isNotEmpty) {
      throw const FormatException('Saved proposal retry data is invalid.');
    }
    final requestId = decoded['requestId'];
    final fingerprint = decoded['payloadFingerprint'];
    if (requestId is! String ||
        !_requestIdPattern.hasMatch(requestId) ||
        fingerprint is! String ||
        !_fingerprintPattern.hasMatch(fingerprint)) {
      throw const FormatException('Saved proposal retry data is invalid.');
    }
    return PendingResidentProposalRequest(
      requestId: requestId,
      payloadFingerprint: fingerprint,
    );
  }

  @override
  Future<void> write({
    required String scopeHash,
    required PendingResidentProposalRequest request,
  }) {
    if (!_requestIdPattern.hasMatch(request.requestId) ||
        !_fingerprintPattern.hasMatch(request.payloadFingerprint)) {
      throw const FormatException('Proposal retry data is invalid.');
    }
    return _storage.write(
      key: _storageKey(scopeHash),
      value: jsonEncode({
        'requestId': request.requestId,
        'payloadFingerprint': request.payloadFingerprint,
      }),
    );
  }

  @override
  Future<void> clearIfMatches({
    required String scopeHash,
    required String requestId,
  }) async {
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw const FormatException('Proposal retry ID is invalid.');
    }
    final pending = await read(scopeHash: scopeHash);
    if (pending?.requestId == requestId) {
      await _storage.delete(key: _storageKey(scopeHash));
    }
  }

  String _storageKey(String scopeHash) {
    if (!_scopeHashPattern.hasMatch(scopeHash)) {
      throw const FormatException('Proposal retry scope is invalid.');
    }
    return '$_keyPrefix.$scopeHash';
  }
}
