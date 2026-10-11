import 'package:cloud_functions/cloud_functions.dart';

import '../application/resident_proposal_boundary.dart';

/// Callable-only proposal boundary. Residents never write Firestore directly.
final class FirebaseResidentProposalBoundary
    implements ResidentProposalBoundary {
  const FirebaseResidentProposalBoundary(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async {
    final result = await functions.httpsCallable('submitResidentProposal').call(
      <String, Object?>{
        'sessionToken': sessionToken,
        'requestId': requestId,
        'title': title,
        'description': description,
        'category': category.wireValue,
        'locationReference': locationReference,
      },
    );
    return ResidentProposalRecord.fromWire(
      _wireMap(result.data, 'resident proposal'),
    );
  }

  @override
  Future<ResidentProposalQueue> listResidentProposals() async {
    final result = await functions
        .httpsCallable('listResidentProposals')
        .call(<String, Object?>{});
    final wire = _wireMap(result.data, 'proposal queue');
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
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async {
    final result = await functions.httpsCallable('reviewResidentProposal').call(
      <String, Object?>{
        'proposalId': proposalId,
        'decision': decision,
        'commandId': commandId,
      },
    );
    return ResidentProposalRecord.fromWire(
      _wireMap(result.data, 'reviewed proposal'),
    );
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
