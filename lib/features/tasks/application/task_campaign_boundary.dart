import 'dart:math';

import 'task_template.dart';
import 'task_location_reference.dart';

/// Trusted boundary for reviewed templates and RT-scoped task commands.
abstract interface class TaskCampaignBoundary {
  Future<List<TaskTemplate>> listApprovedTemplates();

  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
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
    this.activatedAt,
  });

  final String campaignId;
  final String rtId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String status;
  final DateTime? createdAt;
  final String? locationReference;
  final DateTime? activatedAt;

  factory TaskCampaignRecord.fromWire(Map<String, Object?> wire) {
    final snapshot = _asMap(wire['templateSnapshot'], 'templateSnapshot');
    final duration = snapshot['estimatedDurationMinutes'];
    final location = wire['locationReference'];
    if (location != null &&
        (location is! String ||
            !TaskLocationReferences.allowed.contains(location))) {
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
      activatedAt: _optionalDate(wire['activatedAt'], 'activatedAt'),
    );
  }
}

/// Optional active-campaign capability. It is kept separate from the catalog
/// workflow so existing catalog-only boundaries cannot accidentally provide an
/// untrusted local list or cancellation implementation.
abstract interface class TaskCampaignManagementBoundary {
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns();

  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  });
}

/// An active task returned only by the RT-scoped callable endpoint.
final class ActiveTaskCampaignRecord {
  const ActiveTaskCampaignRecord({
    required this.taskId,
    required this.templateSnapshot,
    required this.deadline,
    required this.locationReference,
  });

  final String taskId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String? locationReference;

  factory ActiveTaskCampaignRecord.fromWire(Object? value) {
    final wire = _strictMap(value, 'task');
    _requireOnlyKeys(wire, const {
      'taskId',
      'templateSnapshot',
      'deadline',
      'locationReference',
    });
    final taskId = _requiredString(wire['taskId'], 'taskId');
    if (!_taskIdPattern.hasMatch(taskId)) {
      throw const FormatException('Invalid active task.');
    }

    final rawSnapshot = _strictMap(
      wire['templateSnapshot'],
      'templateSnapshot',
    );
    const snapshotRequiredKeys = {
      'templateId',
      'version',
      'title',
      'category',
      'coreInstruction',
      'safetyInstruction',
    };
    _requireAllowedAndRequiredKeys(rawSnapshot, const {
      ...snapshotRequiredKeys,
      'estimatedDurationMinutes',
    }, snapshotRequiredKeys);
    final duration = rawSnapshot.containsKey('estimatedDurationMinutes')
        ? _requiredInt(
            rawSnapshot['estimatedDurationMinutes'],
            'estimatedDurationMinutes',
          )
        : null;
    final version = _requiredInt(rawSnapshot['version'], 'version');
    final templateId = _requiredString(rawSnapshot['templateId'], 'templateId');
    final category = _requiredString(rawSnapshot['category'], 'category');
    if (version < 1 ||
        !_templateIdPattern.hasMatch(templateId) ||
        !_taskCategories.contains(category) ||
        (duration != null && (duration < 1 || duration > 480))) {
      throw const FormatException('Invalid active task snapshot.');
    }
    final snapshot = TaskTemplateSnapshot(
      templateId: templateId,
      version: version,
      title: _requiredString(rawSnapshot['title'], 'title'),
      category: category,
      coreInstruction: _requiredString(
        rawSnapshot['coreInstruction'],
        'coreInstruction',
      ),
      safetyInstruction: _requiredString(
        rawSnapshot['safetyInstruction'],
        'safetyInstruction',
      ),
      estimatedDurationMinutes: duration,
    );

    final location = wire['locationReference'];
    if (location != null &&
        (location is! String ||
            !TaskLocationReferences.allowed.contains(location))) {
      throw const FormatException('Invalid active task location.');
    }
    return ActiveTaskCampaignRecord(
      taskId: taskId,
      templateSnapshot: snapshot,
      deadline: _requiredActiveDeadline(wire['deadline']),
      locationReference: location as String?,
    );
  }

  static List<ActiveTaskCampaignRecord> listFromWire(Object? value) {
    final payload = _strictMap(value, 'active task response');
    _requireOnlyKeys(payload, const {'tasks'});
    final tasks = payload['tasks'];
    if (tasks is! List || tasks.length > 200) {
      throw const FormatException('Invalid active task response.');
    }
    final ids = <String>{};
    final records = <ActiveTaskCampaignRecord>[];
    for (final item in tasks) {
      final record = ActiveTaskCampaignRecord.fromWire(item);
      if (!ids.add(record.taskId)) {
        throw const FormatException('Invalid active task response.');
      }
      records.add(record);
    }
    return List<ActiveTaskCampaignRecord>.unmodifiable(records);
  }
}

/// The only accepted successful response to a cancellation command.
final class TaskCampaignCancellationRecord {
  const TaskCampaignCancellationRecord({
    required this.taskId,
    required this.status,
  });

  final String taskId;
  final String status;

  factory TaskCampaignCancellationRecord.fromWire(
    Object? value, {
    required String expectedTaskId,
  }) {
    final wire = _strictMap(value, 'cancellation response');
    _requireOnlyKeys(wire, const {'taskId', 'status'});
    final taskId = _requiredString(wire['taskId'], 'taskId');
    final status = _requiredString(wire['status'], 'status');
    if (!_taskIdPattern.hasMatch(taskId) ||
        taskId != expectedTaskId ||
        status != 'CANCELLED') {
      throw const FormatException('Invalid cancellation response.');
    }
    return TaskCampaignCancellationRecord(taskId: taskId, status: status);
  }
}

/// Keeps request IDs stable across network retries for one draft/activation or
/// task cancellation.
final class TaskCampaignController {
  TaskCampaignController(this.boundary, {String Function()? idFactory})
    : _idFactory = idFactory ?? _newOpaqueId;

  final TaskCampaignBoundary boundary;
  final String Function() _idFactory;
  String? _draftRequestId;
  String? _activationCommandId;
  final Map<String, String> _cancellationCommandIds = {};

  Future<List<TaskTemplate>> listApprovedTemplates() =>
      boundary.listApprovedTemplates();

  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      await _managementBoundary.listActiveTaskCampaigns();

  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
  }) async {
    if (!_taskIdPattern.hasMatch(taskId)) {
      throw ArgumentError.value(taskId, 'taskId', 'Invalid task ID.');
    }
    final commandId = _cancellationCommandIds.putIfAbsent(taskId, _idFactory);
    if (!_commandIdPattern.hasMatch(commandId)) {
      throw StateError('The cancellation command ID is invalid.');
    }
    final result = await _managementBoundary.cancelTaskCampaign(
      taskId: taskId,
      commandId: commandId,
    );
    if (result.taskId != taskId || result.status != 'CANCELLED') {
      throw const FormatException('Invalid cancellation response.');
    }
    return result;
  }

  TaskCampaignManagementBoundary get _managementBoundary {
    final value = boundary;
    if (value is TaskCampaignManagementBoundary) {
      return value as TaskCampaignManagementBoundary;
    }
    throw StateError('Active task management is not available.');
  }

  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
  }) async {
    final requestId = _draftRequestId ??= _idFactory();
    final campaign = await boundary.createDraft(
      template: template,
      deadline: deadline,
      locationReference: locationReference,
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

final _taskIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _templateIdPattern = RegExp(r'^[a-z][a-z0-9_-]{0,63}$');
const _taskCategories = {
  'HOUSEHOLD_PREPARATION',
  'LOGISTICS',
  'ENVIRONMENTAL_CLEANUP',
  'SAFE_VISUAL_INSPECTION',
};
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');

Map<String, Object?> _strictMap(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $name.');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireOnlyKeys(Map<String, Object?> wire, Set<String> expected) {
  _requireAllowedAndRequiredKeys(wire, expected, expected);
}

void _requireAllowedAndRequiredKeys(
  Map<String, Object?> wire,
  Set<String> allowed,
  Set<String> required,
) {
  if (wire.keys.any((key) => !allowed.contains(key)) ||
      required.any((key) => !wire.containsKey(key))) {
    throw const FormatException('Invalid callable response.');
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

DateTime _requiredActiveDeadline(Object? value) {
  if (value is! String) {
    throw const FormatException('Invalid active task deadline.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('Invalid active task deadline.');
  }
  return parsed;
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
