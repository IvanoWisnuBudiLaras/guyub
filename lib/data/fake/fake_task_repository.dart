import '../../domain/models/task_campaign.dart';
import '../../domain/models/task_template.dart';
import '../../domain/repositories/task_repository.dart';

/// Seed 2 template persis dari mockup "Katalog Tugas" di proposal.
/// Simpan campaign yang dibuat di memori (in-memory) — hilang tiap hot
/// restart, itu wajar untuk fake repository.
class FakeTaskRepository implements TaskRepository {
  final List<TaskTemplate> _templates = const [
    TaskTemplate(
      templateId: 'tpl-inspeksi-drainase',
      title: 'Inspeksi Saluran Drainase',
      category: 'Infrastruktur',
      coreInstruction:
          'Periksa saluran drainase di sekitar rumah untuk memastikan '
          'tidak ada sumbatan sampah atau sedimen.',
      safetyInstruction:
          '1. Jangan masuk ke saluran yang dalam atau berarus deras.\n'
          '2. Gunakan alas kaki tertutup.\n'
          '3. Dokumentasikan dengan foto dari 2 sudut berbeda.\n'
          '4. Jika ditemukan kerusakan, segera laporkan ke Ketua RT — '
          'jangan mencoba memperbaiki sendiri.',
      estimatedDurationOptional: '~45 menit',
      enabled: true,
      version: 1,
    ),
    TaskTemplate(
      templateId: 'tpl-distribusi-karung-pasir',
      title: 'Distribusi Karung Pasir',
      category: 'Logistik',
      coreInstruction:
          'Bantu mendistribusikan karung pasir ke titik rawan genangan '
          'sesuai arahan Ketua RT.',
      safetyInstruction:
          '1. Angkat dengan teknik yang benar (tekuk lutut, bukan punggung).\n'
          '2. Kerjakan berkelompok minimal 2 orang per karung besar.\n'
          '3. Gunakan sarung tangan bila tersedia.\n'
          '4. Istirahat setiap 15 menit bila cuaca panas/hujan deras.',
      estimatedDurationOptional: '~90 menit',
      enabled: true,
      version: 1,
    ),
  ];

  @override
  Future<List<TaskTemplate>> getEnabledTemplates() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return _templates.where((t) => t.enabled).toList();
  }

  @override
  Future<TaskCampaign> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    String? locationNote,
    String? additionalNote,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    return TaskCampaign(
      taskId: 'draft-${DateTime.now().millisecondsSinceEpoch}',
      rtId: 'rt-03-rw-07',
      templateId: template.templateId,
      templateVersion: template.version,
      // Snapshot di-copy SEKALI di sini, dan tidak pernah berubah lagi
      // walau template aslinya di-update di masa depan (spec §12.8).
      instructionSnapshot: InstructionSnapshot(
        coreInstruction: template.coreInstruction,
        safetyInstruction: template.safetyInstruction,
      ),
      deadline: deadline,
      locationNote: locationNote,
      additionalNote: additionalNote,
      state: TaskCampaignState.draft,
      createdByOperatorUid: 'fake-operator-uid',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<RecipientPreview> getRecipientPreview() async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const RecipientPreview(
      totalCount: 32,
      sampleNames: ['Pak Joko', 'Bu Sari'],
    );
  }

  @override
  Future<TaskCampaign> activateCampaign(TaskCampaign draft) async {
    await Future.delayed(const Duration(milliseconds: 500));

    // TODO(persistence beneran): di implementasi asli, ini WAJIB:
    //  1. Tulis task_campaigns dengan state ACTIVE di Firestore.
    //  2. Tulis 1 audit_events baru ("task sent") — spec §12.13.
    //  3. Trigger Cloud Function notifikasi FCM (Phase 5, belum di sini).
    debugPrintAuditPlaceholder(draft.taskId);

    return draft.copyWith(
      state: TaskCampaignState.active,
      approvedByOperatorUid: 'fake-operator-uid',
      approvedAt: DateTime.now(),
    );
  }

  void debugPrintAuditPlaceholder(String taskId) {
    // Placeholder audit log lokal, BUKAN pengganti audit_events Firestore
    // beneran. Cuma buat mastiin alurnya kepanggil pas testing UI.
    // ignore: avoid_print
    print('[AUDIT-PLACEHOLDER] task sent: $taskId');
  }
}
