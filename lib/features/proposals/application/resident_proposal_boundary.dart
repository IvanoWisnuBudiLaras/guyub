import 'dart:convert';
import 'dart:math';

import '../../auth/application/resident_session_vault.dart';
import '../../tasks/application/task_location_reference.dart';

enum ResidentProposalCategory {
  householdPreparation,
  logistics,
  environmentalCleanup,
  safeVisualInspection,
}

extension ResidentProposalCategoryWire on ResidentProposalCategory {
  String get wireValue => switch (this) {
    ResidentProposalCategory.householdPreparation => 'HOUSEHOLD_PREPARATION',
    ResidentProposalCategory.logistics => 'LOGISTICS',
    ResidentProposalCategory.environmentalCleanup => 'ENVIRONMENTAL_CLEANUP',
    ResidentProposalCategory.safeVisualInspection => 'SAFE_VISUAL_INSPECTION',
  };

  String get label => switch (this) {
    ResidentProposalCategory.householdPreparation => 'Persiapan rumah tangga',
    ResidentProposalCategory.logistics => 'Logistik',
    ResidentProposalCategory.environmentalCleanup => 'Kebersihan lingkungan',
    ResidentProposalCategory.safeVisualInspection =>
      'Pemeriksaan visual dari posisi aman',
  };

  static ResidentProposalCategory fromWire(Object? value) =>
      ResidentProposalCategory.values.firstWhere(
        (category) => category.wireValue == value,
        orElse: () => throw const FormatException('Invalid proposal category.'),
      );
}

abstract interface class ResidentProposalBoundary {
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  });

  Future<ResidentProposalQueue> listResidentProposals();

  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  });
}

final class ResidentProposalRecord {
  const ResidentProposalRecord({
    required this.proposalId,
    required this.title,
    required this.description,
    required this.category,
    required this.state,
    required this.submittedAt,
    this.locationReference,
    this.submitterNickname,
    this.reviewedAt,
  });

  final String proposalId;
  final String title;
  final String description;
  final ResidentProposalCategory category;
  final String state;
  final DateTime submittedAt;
  final String? locationReference;
  final String? submitterNickname;
  final DateTime? reviewedAt;

  factory ResidentProposalRecord.fromWire(Map<String, Object?> wire) {
    final location = wire['locationReference'];
    if (location != null &&
        (location is! String ||
            !TaskLocationReferences.allowed.contains(location))) {
      throw const FormatException('Invalid proposal location.');
    }
    final state = _requiredString(wire['state'], 'state');
    if (state != 'SUBMITTED' && state != 'DISMISSED') {
      throw const FormatException('Invalid proposal state.');
    }
    final proposalId = _requiredString(wire['proposalId'], 'proposalId');
    if (!RegExp(r'^[a-f0-9]{40}$').hasMatch(proposalId)) {
      throw const FormatException('Invalid proposal ID.');
    }
    return ResidentProposalRecord(
      proposalId: proposalId,
      title: _requiredString(wire['title'], 'title'),
      description: _requiredString(wire['description'], 'description'),
      category: ResidentProposalCategoryWire.fromWire(wire['category']),
      state: state,
      submittedAt: _requiredDate(wire['submittedAt'], 'submittedAt'),
      locationReference: location as String?,
      submitterNickname: _optionalString(wire['nickname'], 'nickname'),
      reviewedAt: _optionalDate(wire['reviewedAt'], 'reviewedAt'),
    );
  }
}

final class ResidentProposalQueue {
  const ResidentProposalQueue({required this.items, required this.isPartial});

  final List<ResidentProposalRecord> items;
  final bool isPartial;
}

final class ResidentProposalController {
  ResidentProposalController({
    required this.boundary,
    required this.vault,
    String Function()? requestIdFactory,
  }) : _requestIdFactory = requestIdFactory ?? _newOpaqueId;

  final ResidentProposalBoundary boundary;
  final ResidentSessionVault vault;
  final String Function() _requestIdFactory;
  String? _requestId;
  String? _requestFingerprint;

  Future<ResidentProposalRecord> submit({
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
  }) async {
    final sessionToken = await vault.read();
    if (sessionToken == null || sessionToken.isEmpty) {
      throw StateError('Resident session is unavailable.');
    }
    final fingerprint = jsonEncode([
      title.trim(),
      description.trim(),
      category.wireValue,
      locationReference,
    ]);
    if (_requestFingerprint != fingerprint) {
      _requestId = _requestIdFactory();
      _requestFingerprint = fingerprint;
    }
    final proposal = await boundary.submitResidentProposal(
      sessionToken: sessionToken,
      title: title.trim(),
      description: description.trim(),
      category: category,
      locationReference: locationReference,
      requestId: _requestId!,
    );
    _requestId = null;
    _requestFingerprint = null;
    return proposal;
  }
}

final class ResidentProposalReviewController {
  ResidentProposalReviewController({
    required this.boundary,
    String Function()? commandIdFactory,
  }) : _commandIdFactory = commandIdFactory ?? _newOpaqueId;

  final ResidentProposalBoundary boundary;
  final String Function() _commandIdFactory;
  final Map<String, String> _commandIds = {};

  Future<ResidentProposalQueue> list() => boundary.listResidentProposals();

  Future<ResidentProposalRecord> dismiss(String proposalId) async {
    final commandId = _commandIds.putIfAbsent(proposalId, _commandIdFactory);
    try {
      final result = await boundary.reviewResidentProposal(
        proposalId: proposalId,
        decision: 'DISMISSED',
        commandId: commandId,
      );
      _commandIds.remove(proposalId);
      return result;
    } catch (_) {
      rethrow;
    }
  }
}

String _requiredString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value;
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value;
}

DateTime _requiredDate(Object? value, String name) {
  final date = _optionalDate(value, name);
  if (date == null) throw FormatException('Invalid $name.');
  return date;
}

DateTime? _optionalDate(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $name.');
  return DateTime.tryParse(value)?.toUtc();
}

String _newOpaqueId() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
  final random = Random.secure();
  return List<String>.generate(
    48,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
}
