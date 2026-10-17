import '../../../core/network/callable_client.dart';

import '../application/resident_proposal_boundary.dart';

/// Injectable callable signature makes the adapter testable without Firebase.
typedef ResidentProposalCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, Object?> data,
);

/// Callable-only proposal boundary. Residents never write Firestore directly.
final class FirebaseResidentProposalBoundary
    implements ResidentProposalBoundary {
  const FirebaseResidentProposalBoundary(this.client) : _invoker = null;

  const FirebaseResidentProposalBoundary.withInvoker(this._invoker)
    : client = null;

  final CallableClient? client;
  final ResidentProposalCallableInvoker? _invoker;

  Future<Object?> _call(String name, Map<String, Object?> data) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final client = this.client;
    if (client == null) throw StateError('Callable client unavailable.');
    return client.call(name, data);
  }

  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async {
    final result = await _call('submitResidentProposal', <String, Object?>{
      'sessionToken': sessionToken,
      'requestId': requestId,
      'title': title,
      'description': description,
      'category': category.wireValue,
      'locationReference': locationReference,
    });
    return ResidentProposalRecord.fromWire(
      _wireMap(result, 'resident proposal'),
    );
  }

  @override
  Future<ResidentProposalQueue> listResidentProposals() async {
    final result = await _call('listResidentProposals', <String, Object?>{});
    final wire = _wireMap(result, 'proposal queue');
    final rawItems = wire['items'];
    if (rawItems is! List) {
      throw const FormatException('Invalid proposal queue.');
    }
    return ResidentProposalQueue(
      items: rawItems
          .map(
            (item) =>
                ResidentProposalRecord.fromWire(_wireMap(item, 'proposal')),
          )
          .toList(growable: false),
      isPartial: _requiredBool(wire['isPartial'], 'isPartial'),
    );
  }

  @override
  Future<List<ResidentProposalRecord>> listMyProposals({
    required String sessionToken,
  }) async {
    final result = await _call('listMyResidentProposals', <String, Object?>{
      'sessionToken': sessionToken,
    });
    final wire = _wireMap(result, 'my proposals');
    final rawItems = wire['items'];
    if (rawItems is! List) {
      throw const FormatException('Invalid my proposals response.');
    }
    return rawItems
        .map(
          (item) =>
              ResidentProposalRecord.fromWire(_wireMap(item, 'proposal')),
        )
        .toList(growable: false);
  }

  @override
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async {
    final result = await _call('reviewResidentProposal', <String, Object?>{
      'proposalId': proposalId,
      'decision': decision,
      'commandId': commandId,
    });
    return ResidentProposalRecord.fromWire(
      _wireMap(result, 'reviewed proposal'),
    );
  }

  @override
  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
    required String commandId,
  }) async {
    final result = await _call('mapResidentProposalToDraft', <String, Object?>{
      'proposalId': proposalId,
      'templateId': templateId,
      'version': version,
      'deadline': deadline.toUtc().toIso8601String(),
      'locationReference': locationReference,
      'commandId': commandId,
    });
    return ResidentProposalDraftMapping.fromWire(result);
  }
}

Map<String, Object?> _wireMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Invalid $name.');
}

bool _requiredBool(Object? value, String name) {
  if (value is bool) return value;
  throw FormatException('Invalid $name.');
}
