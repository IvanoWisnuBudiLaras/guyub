import '../../../core/network/callable_client.dart';
import '../application/tree_point_boundary.dart';
import '../domain/tree_point.dart';

typedef TreePointCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, Object?> data,
);

/// Implementasi Firebase Callable untuk boundary titik pohon (Pohon Guyub).
final class FirebaseTreePointBoundary implements TreePointBoundary {
  const FirebaseTreePointBoundary(this.client) : _invoker = null;

  const FirebaseTreePointBoundary.withInvoker(this._invoker) : client = null;

  final CallableClient? client;
  final TreePointCallableInvoker? _invoker;

  Future<Object?> _call(String name, Map<String, Object?> data) async {
    try {
      final invoker = _invoker;
      if (invoker != null) return await invoker(name, data);
      final client = this.client;
      if (client == null) throw StateError('Callable client unavailable.');
      return await client.call(name, data);
    } on CallableException catch (e) {
      _mapCallableException(e);
    }
  }

  Never _mapCallableException(CallableException error) {
    final message = error.message.toLowerCase();
    if (error.code == 'failed-precondition') {
      if (message.contains('akurasi gps')) {
        throw TreePointAccuracyException(error.message);
      }
      throw TreePointConflictException(error.message);
    }
    if (error.code == 'permission-denied') {
      if (message.contains('mock') || message.contains('palsu')) {
        throw TreePointMockLocationException(error.message);
      }
    }
    if (error.code == 'invalid-argument') {
      if (message.contains('nik') ||
          message.contains('telepon') ||
          message.contains('koordinat') ||
          message.contains('sensitif')) {
        throw TreePointSanitizationException(error.message);
      }
    }
    throw TreePointException(
      error.message.isNotEmpty ? error.message : error.code,
    );
  }

  @override
  Future<TreePointSubmissionResult> submitTreePoint({
    required String sessionToken,
    required String taskId,
    String? speciesHint,
    required double exactLat,
    required double exactLng,
    required double accuracyMeters,
    required bool isMocked,
    String? evidenceId,
    required String commandId,
  }) async {
    final payload = <String, Object?>{
      'sessionToken': sessionToken,
      'taskId': taskId,
      'speciesHint': speciesHint,
      'exactLat': exactLat,
      'exactLng': exactLng,
      'accuracyMeters': accuracyMeters,
      'isMocked': isMocked,
      'evidenceId': evidenceId,
      'commandId': commandId,
    };

    final result = await _call('submitTreePoint', payload);
    final wire = _wireMap(result, 'submitTreePoint response');
    final coarseWire = _wireMap(wire['coarseLocation'], 'coarseLocation');

    return TreePointSubmissionResult(
      treePointId: (wire['treePointId'] ?? '').toString(),
      status: TreePointStatus.fromWire((wire['status'] ?? '').toString()),
      coarseLocation: CoarseLocation.fromMap(coarseWire),
      submittedAt:
          DateTime.tryParse((wire['submittedAt'] ?? '').toString())?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  @override
  Future<CommunityTreeMap> listCommunityTreeMap({String? sessionToken}) async {
    final payload = <String, Object?>{};
    if (sessionToken != null) {
      payload['sessionToken'] = sessionToken;
    }

    final result = await _call('listCommunityTreeMap', payload);
    final wire = _wireMap(result, 'listCommunityTreeMap response');
    final rawItems = wire['items'];
    if (rawItems is! List) {
      throw const FormatException('Invalid community tree items list.');
    }

    final items = rawItems
        .map((item) {
          final itemMap = _wireMap(item, 'treeItem');
          final coarseMap = _wireMap(
            itemMap['coarseLocation'],
            'coarseLocation',
          );
          return CommunityTreeItem(
            treePointId: (itemMap['treePointId'] ?? '').toString(),
            speciesHint: itemMap['speciesHint'] as String?,
            submitterNickname: (itemMap['submitterNickname'] ?? '').toString(),
            isAnonymous: itemMap['isAnonymous'] == true,
            coarseLocation: CoarseLocation.fromMap(coarseMap),
            plantedAt:
                DateTime.tryParse((itemMap['plantedAt'] ?? '').toString())
                    ?.toUtc() ??
                DateTime.now().toUtc(),
            hasEvidencePhoto: itemMap['hasEvidencePhoto'] == true,
          );
        })
        .toList(growable: false);

    return CommunityTreeMap(
      items: items,
      totalVerifiedTrees:
          (wire['totalVerifiedTrees'] as num?)?.toInt() ?? items.length,
    );
  }

  @override
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
    required String commandId,
  }) async {
    final payload = <String, Object?>{
      'treePointId': treePointId,
      'decision': decision.toWire(),
      'rejectionReason': rejectionReason,
      'commandId': commandId,
    };

    final result = await _call('verifyTreePoint', payload);
    final wire = _wireMap(result, 'verifyTreePoint response');

    return TreePointVerificationResult(
      treePointId: (wire['treePointId'] ?? '').toString(),
      status: TreePointStatus.fromWire((wire['status'] ?? '').toString()),
      verifiedAt:
          DateTime.tryParse((wire['verifiedAt'] ?? '').toString())?.toUtc() ??
          DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deleteTreePoint({
    required String treePointId,
    String? reason,
  }) async {
    final payload = <String, Object?>{
      'treePointId': treePointId,
      'reason': reason ?? 'Pohon dicabut atau data diperbarui',
    };
    await _call('deleteTreePoint', payload);
  }
}

Map<String, Object?> _wireMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Invalid $name.');
}
