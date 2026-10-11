import 'package:cloud_functions/cloud_functions.dart';

import '../application/task_campaign_boundary.dart';
import '../application/task_template.dart';

/// Callable Functions adapter; task authorization and persistence stay server-side.
typedef TaskCampaignCallableInvoker = Future<Object?> Function(
  String name,
  Map<String, Object?> data,
);

final class FirebaseTaskCampaignBoundary
    implements
        TaskCampaignBoundary,
        TaskCampaignManagementBoundary,
        TaskCampaignHistoryBoundary {
  const FirebaseTaskCampaignBoundary(this.functions) : _invoker = null;

  const FirebaseTaskCampaignBoundary.withInvoker(this._invoker)
    : functions = null;

  final FirebaseFunctions? functions;
  final TaskCampaignCallableInvoker? _invoker;

  Future<Object?> _call(String name, Map<String, Object?> data) async {
    final invoker = _invoker;
    if (invoker != null) return invoker(name, data);
    final functions = this.functions;
    if (functions == null) throw StateError('Callable client unavailable.');
    final result = await functions.httpsCallable(name).call(data);
    return result.data;
  }

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async {
    final result = await _call('listApprovedTaskTemplates', const {});
    final payload = _asMap(result);
    final templates = payload['templates'];
    if (templates is! List) {
      throw const FormatException('Invalid task catalog.');
    }
    return List<TaskTemplate>.unmodifiable(
      templates.map((value) {
        final wire = _asMap(value);
        return TaskTemplate(
          id: _requiredString(wire['templateId'], 'templateId'),
          version: _requiredInt(wire['version'], 'version'),
          title: _requiredString(wire['title'], 'title'),
          category: _requiredString(wire['category'], 'category'),
          coreInstruction: _requiredString(
            wire['coreInstruction'],
            'coreInstruction',
          ),
          safetyInstruction: _requiredString(
            wire['safetyInstruction'],
            'safetyInstruction',
          ),
          enabled: true,
          estimatedDurationMinutes: wire['estimatedDurationMinutes'] == null
              ? null
              : _requiredInt(
                  wire['estimatedDurationMinutes'],
                  'estimatedDurationMinutes',
                ),
        );
      }),
    );
  }

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
  }) async {
    final result = await _call('createTaskDraft', {
      'templateId': template.id,
      'version': template.version,
      'deadline': deadline.toUtc().toIso8601String(),
      'locationReference': locationReference,
      'requestId': requestId,
    });
    return TaskCampaignRecord.fromWire(_asMap(result));
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    final result = await _call('activateTaskCampaign', {
      'campaignId': campaignId,
      'commandId': commandId,
    });
    return TaskCampaignRecord.fromWire(_asMap(result));
  }

  @override
  Future<List<ActiveTaskCampaignRecord>> listActiveTaskCampaigns() async {
    final result = await _call('listActiveTaskCampaigns', const {});
    return ActiveTaskCampaignRecord.listFromWire(result);
  }

  @override
  Future<RtTaskHistoryPage> listRtTaskHistory({
    int pageSize = 25,
    String? cursor,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Must be between 1 and 50.',
      );
    }
    if (cursor != null && !_historyCursorPattern.hasMatch(cursor)) {
      throw ArgumentError.value(cursor, 'cursor', 'Invalid history cursor.');
    }
    final request = <String, Object?>{'pageSize': pageSize};
    if (cursor != null) request['cursor'] = cursor;
    final result = await _call('listRtTaskHistory', request);
    return RtTaskHistoryPage.fromWire(result, pageSize: pageSize);
  }

  @override
  Future<TaskCampaignCancellationRecord> cancelTaskCampaign({
    required String taskId,
    required String commandId,
  }) async {
    if (!_taskIdPattern.hasMatch(taskId) ||
        !_commandIdPattern.hasMatch(commandId)) {
      throw ArgumentError('Invalid task cancellation command.');
    }
    final result = await _call('cancelTaskCampaign', {
      'taskId': taskId,
      'commandId': commandId,
    });
    return TaskCampaignCancellationRecord.fromWire(
      result,
      expectedTaskId: taskId,
    );
  }
}

final _taskIdPattern = RegExp(r'^[a-f0-9]{40}$');
final _commandIdPattern = RegExp(r'^[A-Za-z0-9_-]{32,128}$');
final _historyCursorPattern = RegExp(r'^[A-Za-z0-9_-]{1,256}$');

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw const FormatException('Invalid task response.');
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
