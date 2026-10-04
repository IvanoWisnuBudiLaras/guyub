import 'dart:math';

import 'task_template.dart';

/// Trusted boundary for reviewed templates and RT-scoped task commands.
abstract interface class TaskCampaignBoundary {
  Future<List<TaskTemplate>> listApprovedTemplates();

  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String? additionalNote,
    required String requestId,
  });

  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  });
}

/// Server-authoritative campaign summary returned by callable Functions.
final class TaskCampaignRecord {
  const TaskCampaignRecord({
    required this.campaignId,
    required this.rtId,
    required this.templateSnapshot,
    required this.deadline,
    required this.status,
    required this.createdAt,
    this.locationReference,
    this.additionalNote,
    this.activatedAt,
  });

  final String campaignId;
  final String rtId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String status;
  final DateTime? createdAt;
  final String? locationReference;
  final String? additionalNote;
  final DateTime? activatedAt;

  factory TaskCampaignRecord.fromWire(Map<String, Object?> wire) {
    final snapshot = _asMap(wire['templateSnapshot'], 'templateSnapshot');
    final duration = snapshot['estimatedDurationMinutes'];
    final location = wire['locationReference'];
    final note = wire['additionalNote'];
    if ((location != null && location is! String) ||
        (note != null && note is! String)) {
      throw const FormatException('Invalid campaign parameters.');
    }
    final status = _requiredString(wire['status'], 'status');
    if (status != 'DRAFT' && status != 'ACTIVE') {
      throw const FormatException('Invalid campaign status.');
    }
    return TaskCampaignRecord(
      campaignId: _requiredString(wire['campaignId'], 'campaignId'),
      rtId: _requiredString(wire['rtId'], 'rtId'),
      templateSnapshot: TaskTemplateSnapshot(
        templateId: _requiredString(snapshot['templateId'], 'templateId'),
        version: _requiredInt(snapshot['version'], 'version'),
        title: _requiredString(snapshot['title'], 'title'),
        category: _requiredString(snapshot['category'], 'category'),
        coreInstruction: _requiredString(
          snapshot['coreInstruction'],
          'coreInstruction',
        ),
        safetyInstruction: _requiredString(
          snapshot['safetyInstruction'],
          'safetyInstruction',
        ),
        estimatedDurationMinutes: duration == null
            ? null
            : _requiredInt(duration, 'estimatedDurationMinutes'),
      ),
      deadline: _requiredDate(wire['deadline'], 'deadline'),
      status: status,
      createdAt: _optionalDate(wire['createdAt'], 'createdAt'),
      locationReference: location as String?,
      additionalNote: note as String?,
      activatedAt: _optionalDate(wire['activatedAt'], 'activatedAt'),
    );
  }
}

/// Keeps request IDs stable across network retries for one draft/activation.
final class TaskCampaignController {
  TaskCampaignController(this.boundary, {String Function()? idFactory})
    : _idFactory = idFactory ?? _newOpaqueId;

  final TaskCampaignBoundary boundary;
  final String Function() _idFactory;
  String? _draftRequestId;
  String? _activationCommandId;

  Future<List<TaskTemplate>> listApprovedTemplates() =>
      boundary.listApprovedTemplates();

  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String? additionalNote,
  }) async {
    final requestId = _draftRequestId ??= _idFactory();
    final campaign = await boundary.createDraft(
      template: template,
      deadline: deadline,
      locationReference: locationReference,
      additionalNote: additionalNote,
      requestId: requestId,
    );
    _draftRequestId = null;
    return campaign;
  }

  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
  }) async {
    final commandId = _activationCommandId ??= _idFactory();
    final campaign = await boundary.activateCampaign(
      campaignId: campaignId,
      commandId: commandId,
    );
    _activationCommandId = null;
    return campaign;
  }
}

Map<String, Object?> _asMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw FormatException('Invalid $name.');
}

String _requiredString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value;
}

int _requiredInt(Object? value, String name) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Invalid $name.');
}

DateTime _requiredDate(Object? value, String name) {
  final result = _optionalDate(value, name);
  if (result == null) throw FormatException('Invalid $name.');
  return result;
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
