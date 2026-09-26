import '../models/task_campaign.dart';
import '../models/task_template.dart';

/// Kontrak untuk Task Catalog (SCR-09) & Send Confirmation (SCR-10).
///
/// PENTING (INV-01, INV-02 — hard constraint, lihat spec §6):
/// - createDraft() TIDAK BOLEH langsung menghasilkan state ACTIVE.
/// - Hanya activateCampaign() yang boleh transisi DRAFT -> ACTIVE, dan itu
///   harus merepresentasikan tindakan operator yang eksplisit & sadar
///   (tombol "Kirim Ke Warga" di SCR-10) — bukan otomatis.
/// - activateCampaign() wajib mencatat audit_event ("task sent") di balik
///   layar — lihat spec §12.13.
abstract class TaskRepository {
  Future<List<TaskTemplate>> getEnabledTemplates();

  /// Membuat campaign berstatus DRAFT dari template terkunci + slot yang
  /// boleh diedit operator (deadline/locationNote/additionalNote).
  Future<TaskCampaign> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    String? locationNote,
    String? additionalNote,
  });

  /// Estimasi jumlah & preview nama warga penerima, untuk ditampilkan di
  /// layar konfirmasi sebelum operator kirim.
  Future<RecipientPreview> getRecipientPreview();

  /// Transisi DRAFT -> ACTIVE. Ini titik "human approval before
  /// distribution" (INV-01) — harus dipanggil dari tap eksplisit di UI,
  /// tidak pernah otomatis.
  Future<TaskCampaign> activateCampaign(TaskCampaign draft);
}