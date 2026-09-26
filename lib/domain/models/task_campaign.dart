/// State sesuai spec §10.1 — INI ENGINEERING DERIVATION resmi dari dokumen,
/// jangan tambah/ubah nama state sendiri.
///
/// SUGGESTED -> DRAFT -> ACTIVE -> (CLOSED | CANCELLED_BY_OPERATOR)
enum TaskCampaignState {
  suggested,
  draft,
  active,
  closed,
  cancelledByOperator,
}

/// Snapshot instruksi yang di-copy dari template saat campaign dibuat.
/// Immutable — kalau template diedit/versi baru nanti, campaign lama TETAP
/// pakai snapshot ini (spec §12.8: "Keep an immutable snapshot so old task
/// history does not change if a template is edited later").
class InstructionSnapshot {
  const InstructionSnapshot({
    required this.coreInstruction,
    required this.safetyInstruction,
  });

  final String coreInstruction;
  final String safetyInstruction;
}

/// Sesuai spec §12.8 `task_campaigns`.
class TaskCampaign {
  const TaskCampaign({
    required this.taskId,
    required this.rtId,
    required this.templateId,
    required this.templateVersion,
    required this.instructionSnapshot,
    required this.deadline,
    this.locationNote,
    this.additionalNote,
    required this.state,
    required this.createdByOperatorUid,
    this.approvedByOperatorUid,
    required this.createdAt,
    this.approvedAt,
  });

  final String taskId;
  final String rtId;
  final String templateId;
  final int templateVersion;
  final InstructionSnapshot instructionSnapshot;
  final DateTime deadline;
  final String? locationNote;
  final String? additionalNote;
  final TaskCampaignState state;
  final String createdByOperatorUid;
  final String? approvedByOperatorUid;
  final DateTime createdAt;
  final DateTime? approvedAt;

  TaskCampaign copyWith({
    TaskCampaignState? state,
    String? approvedByOperatorUid,
    DateTime? approvedAt,
  }) {
    return TaskCampaign(
      taskId: taskId,
      rtId: rtId,
      templateId: templateId,
      templateVersion: templateVersion,
      instructionSnapshot: instructionSnapshot,
      deadline: deadline,
      locationNote: locationNote,
      additionalNote: additionalNote,
      state: state ?? this.state,
      createdByOperatorUid: createdByOperatorUid,
      approvedByOperatorUid: approvedByOperatorUid ?? this.approvedByOperatorUid,
      createdAt: createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
    );
  }
}

/// Preview penerima untuk layar Konfirmasi (SCR-10) — "recipient count",
/// "recipient preview" di spec. Sumber data resident scoped-RT sesungguhnya
/// belum ada di Phase 2 (itu Phase 3), jadi ini masih dummy count di fake repo.
class RecipientPreview {
  const RecipientPreview({required this.totalCount, required this.sampleNames});
  final int totalCount;
  final List<String> sampleNames;
}
