import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../auth/application/resident_session_vault.dart';
import '../../tasks/application/task_location_reference.dart';
import '../../tasks/application/task_campaign_boundary.dart';
import '../../tasks/application/task_template.dart';

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

  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
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
    if (state != 'SUBMITTED' &&
        state != 'DISMISSED' &&
        state != 'NEEDS_OFFICIAL_REPORT' &&
        state != 'MAPPED_TO_SAFE_TEMPLATE') {
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

/// The callable confirms proposal review and returns a task campaign that must
/// still be explicitly activated by the operator.
final class ResidentProposalDraftMapping {
  const ResidentProposalDraftMapping({
    required this.proposalId,
    required this.state,
    required this.reviewedAt,
    required this.campaign,
  });

  final String proposalId;
  final String state;
  final DateTime reviewedAt;
  final TaskCampaignRecord campaign;

  factory ResidentProposalDraftMapping.fromWire(Object? value) {
    final wire = _strictMap(value, 'proposal mapping');
    _requireExactKeys(wire, const {'proposal', 'campaign'});
    final proposal = _strictMap(wire['proposal'], 'mapped proposal');
    _requireExactKeys(proposal, const {
      'proposalId',
      'title',
      'description',
      'category',
      'locationReference',
      'state',
      'submittedAt',
      'reviewedAt',
    });
    final proposalId = _requiredString(proposal['proposalId'], 'proposalId');
    if (!_proposalIdPattern.hasMatch(proposalId) ||
        _requiredString(proposal['state'], 'proposal state') !=
            'MAPPED_TO_SAFE_TEMPLATE') {
      throw const FormatException('Invalid mapped proposal.');
    }
    final reviewedAt = _requiredDate(proposal['reviewedAt'], 'reviewedAt');
    _requiredString(proposal['title'], 'proposal title');
    _requiredString(proposal['description'], 'proposal description');
    ResidentProposalCategoryWire.fromWire(proposal['category']);
    _requiredDate(proposal['submittedAt'], 'submittedAt');
    final proposalLocation = proposal['locationReference'];
    if (proposalLocation != null &&
        (proposalLocation is! String ||
            !TaskLocationReferences.allowed.contains(proposalLocation))) {
      throw const FormatException('Invalid mapped proposal location.');
    }

    final campaignWire = _strictMap(wire['campaign'], 'mapped campaign');
    _requireExactKeys(campaignWire, const {
      'campaignId',
      'rtId',
      'templateSnapshot',
      'deadline',
      'locationReference',
      'status',
      'createdAt',
      'activatedAt',
    });
    if (campaignWire['activatedAt'] != null ||
        _requiredString(campaignWire['status'], 'campaign status') != 'DRAFT') {
      throw const FormatException('Mapped campaign must remain a draft.');
    }
    final snapshot = _strictMap(
      campaignWire['templateSnapshot'],
      'template snapshot',
    );
    _requireRequiredKeys(
      snapshot,
      const {
        'templateId',
        'version',
        'title',
        'category',
        'coreInstruction',
        'safetyInstruction',
      },
      const {
        'templateId',
        'version',
        'title',
        'category',
        'coreInstruction',
        'safetyInstruction',
        'estimatedDurationMinutes',
      },
    );
    final templateId = _requiredString(snapshot['templateId'], 'templateId');
    final version = _requiredInt(snapshot['version'], 'version');
    final category = _requiredString(snapshot['category'], 'category');
    final duration = snapshot['estimatedDurationMinutes'];
    if (!_templateIdPattern.hasMatch(templateId) ||
        version < 1 ||
        !_taskCategories.contains(category) ||
        (duration != null &&
            (_requiredInt(duration, 'estimatedDurationMinutes') < 1 ||
                _requiredInt(duration, 'estimatedDurationMinutes') > 480))) {
      throw const FormatException('Invalid mapped template snapshot.');
    }
    _requiredString(snapshot['title'], 'template title');
    _requiredString(snapshot['coreInstruction'], 'core instruction');
    _requiredString(snapshot['safetyInstruction'], 'safety instruction');
    _requiredString(campaignWire['campaignId'], 'campaignId');
    _requiredString(campaignWire['rtId'], 'rtId');
    _requiredDate(campaignWire['deadline'], 'deadline');
    _requiredDate(campaignWire['createdAt'], 'createdAt');
    final location = campaignWire['locationReference'];
    if (location != null &&
        (location is! String ||
            !TaskLocationReferences.allowed.contains(location))) {
      throw const FormatException('Invalid mapped campaign location.');
    }
    final campaign = TaskCampaignRecord.fromWire(campaignWire);
    if (campaign.createdAt == null || campaign.activatedAt != null) {
      throw const FormatException('Invalid mapped campaign lifecycle.');
    }
    return ResidentProposalDraftMapping(
      proposalId: proposalId,
      state: 'MAPPED_TO_SAFE_TEMPLATE',
      reviewedAt: reviewedAt,
      campaign: campaign,
    );
  }
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

  Future<ResidentProposalRecord> markNeedsOfficialReport(
    String proposalId,
  ) async {
    final commandId = _commandIds.putIfAbsent(proposalId, _commandIdFactory);
    try {
      final result = await boundary.reviewResidentProposal(
        proposalId: proposalId,
        decision: 'NEEDS_OFFICIAL_REPORT',
        commandId: commandId,
      );
      _commandIds.remove(proposalId);
      return result;
    } catch (_) {
      rethrow;
    }
  }

  Future<ResidentProposalDraftMapping> mapToDraft({
    required String proposalId,
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
  }) async {
    if (!_proposalIdPattern.hasMatch(proposalId) ||
        !_templateIdPattern.hasMatch(template.id) ||
        template.version < 1 ||
        !template.enabled ||
        !deadline.isAfter(DateTime.now()) ||
        (locationReference != null &&
            !TaskLocationReferences.allowed.contains(locationReference))) {
      throw ArgumentError('Invalid safe-template mapping selection.');
    }
    final utcDeadline = deadline.toUtc();
    final commandId = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'resident-proposal-map-v1',
              proposalId,
              template.id,
              template.version,
              utcDeadline.toIso8601String(),
              locationReference,
            ]),
          ),
        )
        .toString();
    if (!_commandIdPattern.hasMatch(commandId)) {
      throw StateError('The proposal mapping command ID is invalid.');
    }
    final mapping = await boundary.mapResidentProposalToDraft(
      proposalId: proposalId,
      templateId: template.id,
      version: template.version,
      deadline: utcDeadline,
      locationReference: locationReference,
      commandId: commandId,
    );
    final campaign = mapping.campaign;
    if (mapping.proposalId != proposalId ||
        mapping.state != 'MAPPED_TO_SAFE_TEMPLATE' ||
        campaign.status != 'DRAFT' ||
        campaign.activatedAt != null ||
        campaign.templateSnapshot.templateId != template.id ||
        campaign.templateSnapshot.version != template.version ||
        !campaign.deadline.isAtSameMomentAs(utcDeadline) ||
        campaign.locationReference != locationReference) {
      throw const FormatException('Proposal mapping response did not match.');
    }
    return mapping;
  }
}

final _proposalIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _templateIdPattern = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
const _taskCategories = {
  'HOUSEHOLD_PREPARATION',
  'LOGISTICS',
  'ENVIRONMENTAL_CLEANUP',
  'SAFE_VISUAL_INSPECTION',
};

Map<String, Object?> _strictMap(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $name.');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> wire, Set<String> keys) {
  if (wire.length != keys.length ||
      wire.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Invalid proposal mapping payload.');
  }
}

void _requireRequiredKeys(
  Map<String, Object?> wire,
  Set<String> required,
  Set<String> allowed,
) {
  if (required.any((key) => !wire.containsKey(key)) ||
      wire.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Invalid proposal mapping payload.');
  }
}

int _requiredInt(Object? value, String name) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Invalid $name.');
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
