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

/// Optional callable capability for reading a server-derived RT task history.
/// Kept separate so existing management fakes/implementations do not gain an
/// accidental local or unscoped history implementation.
abstract interface class TaskCampaignHistoryBoundary {
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  });
}

/// History reads are exposed through the management boundary but supplied only
/// by adapters that implement [TaskCampaignHistoryBoundary].
extension TaskCampaignHistoryManagement on TaskCampaignManagementBoundary {
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) {
    _validateRtTaskHistoryRequest(pageSize: pageSize, cursor: cursor);
    final historyBoundary = this;
    if (historyBoundary is! TaskCampaignHistoryBoundary) {
      throw StateError('RT task history is not available.');
    }
    return (historyBoundary as TaskCampaignHistoryBoundary).listRtTaskHistory(
      pageSize: pageSize,
      cursor: cursor,
    );
  }
}

/// Separate capability for explicit close commands and privacy-safe event reads.
/// Keeping it optional preserves older test boundaries and implementations.
abstract interface class TaskCampaignLifecycleBoundary {
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  });

  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  });
}

extension TaskCampaignLifecycleManagement on TaskCampaignManagementBoundary {
  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
    required String commandId,
  }) {
    final lifecycleBoundary = this;
    if (lifecycleBoundary is! TaskCampaignLifecycleBoundary) {
      throw StateError('Task lifecycle commands are not available.');
    }
    return (lifecycleBoundary as TaskCampaignLifecycleBoundary)
        .closeTaskCampaign(taskId: taskId, commandId: commandId);
  }

  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) {
    final lifecycleBoundary = this;
    if (lifecycleBoundary is! TaskCampaignLifecycleBoundary) {
      throw StateError('Task lifecycle history is not available.');
    }
    return (lifecycleBoundary as TaskCampaignLifecycleBoundary)
        .listTaskLifecycleEvents(taskId: taskId);
  }
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

/// One historical task from the server-authoritative RT history callable.
/// The wire shape intentionally contains no resident response or profile data.
final class RtTaskHistoryRecord {
  const RtTaskHistoryRecord({
    required this.taskId,
    required this.templateSnapshot,
    required this.deadline,
    required this.status,
    required this.activatedAt,
    required this.cancelledAt,
    required this.closedAt,
    required this.locationReference,
  });

  final String taskId;
  final TaskTemplateSnapshot templateSnapshot;
  final DateTime deadline;
  final String? locationReference;
  final String status;
  final DateTime activatedAt;
  final DateTime? cancelledAt;
  final DateTime? closedAt;

  factory RtTaskHistoryRecord.fromWire(Object? value) {
    final wire = _strictMap(value, 'history task');
    _requireOnlyKeys(wire, const {
      'taskId',
      'templateSnapshot',
      'deadline',
      'locationReference',
      'status',
      'activatedAt',
      'cancelledAt',
      'closedAt',
    });
    final taskId = _requiredString(wire['taskId'], 'taskId');
    if (!_taskIdPattern.hasMatch(taskId)) {
      throw const FormatException('Invalid history task.');
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
      throw const FormatException('Invalid history task snapshot.');
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
      throw const FormatException('Invalid history task location.');
    }
    final status = _requiredString(wire['status'], 'status');
    if (status != 'ACTIVE' && status != 'CLOSED' && status != 'CANCELLED') {
      throw const FormatException('Invalid history task status.');
    }
    final activatedAt = _requiredUtcDate(wire['activatedAt'], 'activatedAt');
    final cancelledAt = wire['cancelledAt'] == null
        ? null
        : _requiredUtcDate(wire['cancelledAt'], 'cancelledAt');
    final closedAt = wire['closedAt'] == null
        ? null
        : _requiredUtcDate(wire['closedAt'], 'closedAt');
    if ((status == 'ACTIVE' && (cancelledAt != null || closedAt != null)) ||
        (status == 'CLOSED' && (cancelledAt != null || closedAt == null)) ||
        (status == 'CANCELLED' && (cancelledAt == null || closedAt != null))) {
      throw const FormatException('Invalid history task status dates.');
    }

    return RtTaskHistoryRecord(
      taskId: taskId,
      templateSnapshot: snapshot,
      deadline: _requiredUtcDate(wire['deadline'], 'deadline'),
      locationReference: location as String?,
      status: status,
      activatedAt: activatedAt,
      cancelledAt: cancelledAt,
      closedAt: closedAt,
    );
  }
}

/// A bounded page of history returned by the RT-scoped callable endpoint.
final class RtTaskHistoryPage {
  const RtTaskHistoryPage({required this.tasks, required this.nextCursor});

  final List<RtTaskHistoryRecord> tasks;
  final String? nextCursor;

  factory RtTaskHistoryPage.fromWire(Object? value, {int pageSize = 50}) {
    _validateRtTaskHistoryRequest(pageSize: pageSize);
    final wire = _strictMap(value, 'history response');
    _requireOnlyKeys(wire, const {'tasks', 'nextCursor'});
    final rawTasks = wire['tasks'];
    if (rawTasks is! List || rawTasks.length > pageSize) {
      throw const FormatException('Invalid history response.');
    }
    final ids = <String>{};
    final tasks = <RtTaskHistoryRecord>[];
    for (final value in rawTasks) {
      final task = RtTaskHistoryRecord.fromWire(value);
      if (!ids.add(task.taskId)) {
        throw const FormatException('Invalid history response.');
      }
      tasks.add(task);
    }
    final rawCursor = wire['nextCursor'];
    if (rawCursor != null &&
        (rawCursor is! String ||
            !_taskHistoryCursorPattern.hasMatch(rawCursor))) {
      throw const FormatException('Invalid history cursor.');
    }
    return RtTaskHistoryPage(
      tasks: List<RtTaskHistoryRecord>.unmodifiable(tasks),
      nextCursor: rawCursor as String?,
    );
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

/// The only accepted successful response to an explicit close command.
final class TaskCampaignClosureRecord {
  const TaskCampaignClosureRecord({required this.taskId, required this.status});

  final String taskId;
  final String status;

  factory TaskCampaignClosureRecord.fromWire(
    Object? value, {
    required String expectedTaskId,
  }) {
    final wire = _strictMap(value, 'closure response');
    _requireOnlyKeys(wire, const {'taskId', 'status'});
    final taskId = _requiredString(wire['taskId'], 'taskId');
    final status = _requiredString(wire['status'], 'status');
    if (!_taskIdPattern.hasMatch(taskId) ||
        taskId != expectedTaskId ||
        status != 'CLOSED') {
      throw const FormatException('Invalid closure response.');
    }
    return TaskCampaignClosureRecord(taskId: taskId, status: status);
  }
}

/// A lifecycle-only history projection. It intentionally contains no actor,
/// campaign, response, or resident identifiers.
final class RtTaskLifecycleEvent {
  const RtTaskLifecycleEvent({
    required this.eventType,
    required this.occurredAt,
  });

  final String eventType;
  final DateTime occurredAt;

  factory RtTaskLifecycleEvent.fromWire(Object? value) {
    final wire = _strictMap(value, 'lifecycle event');
    _requireOnlyKeys(wire, const {'eventType', 'occurredAt'});
    final eventType = _requiredString(wire['eventType'], 'eventType');
    if (!const {'ACTIVATED', 'CLOSED', 'CANCELLED'}.contains(eventType)) {
      throw const FormatException('Invalid lifecycle event.');
    }
    return RtTaskLifecycleEvent(
      eventType: eventType,
      occurredAt: _requiredUtcDate(wire['occurredAt'], 'occurredAt'),
    );
  }

  static List<RtTaskLifecycleEvent> listFromWire(Object? value) {
    final wire = _strictMap(value, 'lifecycle event response');
    _requireOnlyKeys(wire, const {'events'});
    final rawEvents = wire['events'];
    if (rawEvents is! List || rawEvents.isEmpty || rawEvents.length > 3) {
      throw const FormatException('Invalid lifecycle event response.');
    }
    final events = rawEvents.map(RtTaskLifecycleEvent.fromWire).toList();
    final validSequence =
        events.first.eventType == 'ACTIVATED' &&
        (events.length == 1 ||
            (events.length == 2 &&
                (events.last.eventType == 'CLOSED' ||
                    events.last.eventType == 'CANCELLED')));
    for (var index = 1; index < events.length; index++) {
      if (events[index].occurredAt.isBefore(events[index - 1].occurredAt)) {
        throw const FormatException('Invalid lifecycle event order.');
      }
    }
    if (!validSequence) {
      throw const FormatException('Invalid lifecycle event sequence.');
    }
    return List<RtTaskLifecycleEvent>.unmodifiable(events);
  }
}

/// Keeps request IDs stable across network retries for one draft/activation or
/// task cancellation/closure.
final class TaskCampaignController {
  TaskCampaignController(this.boundary, {String Function()? idFactory})
    : _idFactory = idFactory ?? _newOpaqueId;

  final TaskCampaignBoundary boundary;
  final String Function() _idFactory;
  String? _draftRequestId;
  String? _activationCommandId;
  final Map<String, String> _cancellationCommandIds = {};
  final Map<String, String> _closureCommandIds = {};

  Future<List<TaskTemplate>> listApprovedTemplates() =>
      boundary.listApprovedTemplates();

  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async =>
      await _managementBoundary.listActiveTaskCampaigns();

  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async {
    _validateRtTaskHistoryRequest(pageSize: pageSize, cursor: cursor);
    return _managementBoundary.listRtTaskHistory(
      pageSize: pageSize,
      cursor: cursor,
    );
  }

  Future<List<RtTaskLifecycleEvent>> listTaskLifecycleEvents({
    required String taskId,
  }) async {
    if (!_taskIdPattern.hasMatch(taskId)) {
      throw ArgumentError.value(taskId, 'taskId', 'Invalid task ID.');
    }
    return _managementBoundary.listTaskLifecycleEvents(taskId: taskId);
  }

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

  Future<TaskCampaignClosureRecord> closeTaskCampaign({
    required String taskId,
  }) async {
    if (!_taskIdPattern.hasMatch(taskId)) {
      throw ArgumentError.value(taskId, 'taskId', 'Invalid task ID.');
    }
    final commandId = _closureCommandIds.putIfAbsent(taskId, _idFactory);
    if (!_commandIdPattern.hasMatch(commandId)) {
      throw StateError('The closure command ID is invalid.');
    }
    final result = await _managementBoundary.closeTaskCampaign(
      taskId: taskId,
      commandId: commandId,
    );
    if (result.taskId != taskId || result.status != 'CLOSED') {
      throw const FormatException('Invalid closure response.');
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
final _taskHistoryCursorPattern = RegExp(r'^[A-Za-z0-9_-]{1,256}$');

void _validateRtTaskHistoryRequest({required int pageSize, String? cursor}) {
  if (pageSize < 1 || pageSize > 50) {
    throw ArgumentError.value(
      pageSize,
      'pageSize',
      'Must be between 1 and 50.',
    );
  }
  if (cursor != null && !_taskHistoryCursorPattern.hasMatch(cursor)) {
    throw ArgumentError.value(cursor, 'cursor', 'Must be a base64url cursor.');
  }
}

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

DateTime _requiredUtcDate(Object? value, String name) {
  if (value is! String) throw FormatException('Invalid $name.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw FormatException('Invalid $name.');
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
