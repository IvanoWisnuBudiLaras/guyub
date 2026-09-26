/// Sesuai spec §12.6 `task_templates`. Core & safety text WAJIB immutable
/// di sisi UI operator — INV-02. Jangan pernah bikin TextField yang nulis
/// ke coreInstruction/safetyInstruction dari layar operator manapun.
class TaskTemplate {
  const TaskTemplate({
    required this.templateId,
    required this.title,
    required this.category,
    required this.coreInstruction,
    required this.safetyInstruction,
    this.estimatedDurationOptional,
    required this.enabled,
    required this.version,
  });

  final String templateId;
  final String title;
  final String category; // "Infrastruktur", "Logistik", dll (spec §12.6)
  final String coreInstruction;
  final String safetyInstruction;
  final String? estimatedDurationOptional; // mis. "~45 menit"
  final bool enabled;
  final int version;
}
