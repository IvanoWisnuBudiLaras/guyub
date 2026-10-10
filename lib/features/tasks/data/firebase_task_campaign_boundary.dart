import 'package:cloud_functions/cloud_functions.dart';

import '../application/task_campaign_boundary.dart';
import '../application/task_template.dart';

/// Callable Functions adapter; task authorization and persistence stay server-side.
final class FirebaseTaskCampaignBoundary implements TaskCampaignBoundary {
  const FirebaseTaskCampaignBoundary(this.functions);

  final FirebaseFunctions functions;

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async {
    final result = await functions
        .httpsCallable('listApprovedTaskTemplates')
        .call();
    final payload = _asMap(result.data);
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
    final result = await functions.httpsCallable('createTaskDraft').call({
      'templateId': template.id,
      'version': template.version,
      'deadline': deadline.toUtc().toIso8601String(),
      'locationReference': locationReference,
      'requestId': requestId,
    });
    return TaskCampaignRecord.fromWire(_asMap(result.data));
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    final result = await functions.httpsCallable('activateTaskCampaign').call({
      'campaignId': campaignId,
      'commandId': commandId,
    });
    return TaskCampaignRecord.fromWire(_asMap(result.data));
  }
}

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
