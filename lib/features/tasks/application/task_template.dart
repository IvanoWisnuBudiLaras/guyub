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
  }) {
    _requireText(id, 'id');
    _requireText(title, 'title');
    _requireText(category, 'category');
    _requireText(coreInstruction, 'coreInstruction');
    _requireText(safetyInstruction, 'safetyInstruction');
    if (version < 1) {
      throw ArgumentError.value(version, 'version', 'Must be positive.');
    }
  }

  final String id;
  final int version;
  final String title;
  final String category;
  final String coreInstruction;
  final String safetyInstruction;
  final bool enabled;

  TaskTemplateSnapshot snapshot() => TaskTemplateSnapshot(
    templateId: id,
    version: version,
    title: title,
    category: category,
    coreInstruction: coreInstruction,
    safetyInstruction: safetyInstruction,
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
  });

  final String templateId;
  final int version;
  final String title;
  final String category;
  final String coreInstruction;
  final String safetyInstruction;
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}
