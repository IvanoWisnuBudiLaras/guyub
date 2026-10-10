/// A single reviewed entry from the controlled resident-task catalog.
///
/// The app must obtain templates from an approved catalog boundary. Constructing
/// this value only validates its shape; it does not prove that the content was
/// reviewed or authorize its use in production.
final class TaskTemplate {
  TaskTemplate({
    required this.id,
    required this.version,
    required this.title,
    required this.category,
    required this.coreInstruction,
    required this.safetyInstruction,
    required this.enabled,
    this.estimatedDurationMinutes,
  }) {
    _requireText(id, 'id');
    _requireText(title, 'title');
    _requireText(category, 'category');
    _requireText(coreInstruction, 'coreInstruction');
    _requireText(safetyInstruction, 'safetyInstruction');
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
    if (estimatedDurationMinutes != null &&
        (estimatedDurationMinutes! < 1 || estimatedDurationMinutes! > 480)) {
      throw ArgumentError.value(
        estimatedDurationMinutes,
        'estimatedDurationMinutes',
        'Must be between 1 and 480 minutes when provided.',
      );
    }
  }

  final String id;
  final int version;
  final String title;
  final String category;
  final String coreInstruction;
  final String safetyInstruction;
  final bool enabled;
  final int? estimatedDurationMinutes;

  TaskTemplateSnapshot snapshot() => TaskTemplateSnapshot(
    templateId: id,
    version: version,
    title: title,
    category: category,
    coreInstruction: coreInstruction,
    safetyInstruction: safetyInstruction,
    estimatedDurationMinutes: estimatedDurationMinutes,
  );
}

/// Immutable copy of the reviewed template content stored with a campaign.
final class TaskTemplateSnapshot {
  const TaskTemplateSnapshot({
    required this.templateId,
    required this.version,
    required this.title,
    required this.category,
    required this.coreInstruction,
    required this.safetyInstruction,
    this.estimatedDurationMinutes,
  });

  final String templateId;
  final int version;
  final String title;
  final String category;
  final String coreInstruction;
  final String safetyInstruction;
  final int? estimatedDurationMinutes;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}
