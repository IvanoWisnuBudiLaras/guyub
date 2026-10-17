import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/assistance/application/assistance_volunteer_boundary.dart';
import '../../features/assistance/application/proxy_resident_boundary.dart';
import '../../features/auth/application/operator_auth_boundary.dart';
import '../../features/auth/application/operator_profile.dart';
import '../../features/auth/application/resident_session.dart';
import '../../features/auth/application/resident_session_boundary.dart';
import '../../features/emergency/application/emergency_directory.dart';
import '../../features/emergency/application/emergency_directory_boundary.dart';
import '../../features/evidence/application/task_evidence_boundary.dart';
import '../../features/proposals/application/resident_proposal_boundary.dart';
import '../../features/tasks/application/task_campaign_boundary.dart';
import '../../features/tasks/application/task_response.dart';
import '../../features/tasks/application/task_response_boundary.dart';
import '../../features/tasks/application/task_template.dart';
import '../../features/trees/application/tree_point_boundary.dart';
import '../../features/trees/domain/tree_point.dart';
import '../../features/weather/application/weather_snapshot.dart';
import '../../features/weather/application/weather_snapshot_boundary.dart';
import '../../features/weather/application/weather_suggestion.dart';
import '../../features/weather/application/weather_suggestion_boundary.dart';
import '../result/app_error.dart';
import '../result/result.dart';

/// Mesin Demo Mandiri (Standalone Demo Engine) untuk Pengujian Juri.
///
/// Menyediakan stateful in-memory boundaries sehingga aplikasi Guyub.id dapat
/// diuji secara 100% fungsional tanpa bergantung pada koneksi internet, backend
/// laptop, atau akun Firebase berbayar.
final class StandaloneDemoEngine {
  StandaloneDemoEngine._() {
    _initPreseededData();
  }

  static final StandaloneDemoEngine instance = StandaloneDemoEngine._();

  OperatorProfile? activeOperator;
  ResidentSession? activeResident;

  final List<TaskCampaignRecord> _campaigns = [];
  final List<ResidentTaskRecord> _residentTasks = [];
  final List<ResidentProposalRecord> _proposals = [];
  final List<CommunityTreeItem> _trees = [];
  final List<TaskVerificationRecord> _pendingVerifications = [];
  final List<ProxyResidentRecord> _proxyResidents = [];

  void _initPreseededData() {
    final now = DateTime.now();

    // 1. Template bawaan
    final templateTasSiaga = TaskTemplateSnapshot(
      templateId: 'tas_siaga_keluarga',
      version: 1,
      title: 'Siapkan Tas Siaga & Dokumen Penting',
      category: 'HOUSEHOLD_PREPARATION',
      coreInstruction: 'Kumpulkan dokumen KK, KTP, ijazah, surat berharga, obat pribadi, senter, dan pakaian ganti ke dalam tas tahan air.',
      safetyInstruction: 'Jangan meletakkan dokumen berharga di lantai dasar. Letakkan tas di area mudah dijangkau saat darurat.',
      estimatedDurationMinutes: 30,
    );

    final templateSaluran = TaskTemplateSnapshot(
      templateId: 'bersihkan_saluran_depan',
      version: 1,
      title: 'Pembersihan Saluran Air Depan Rumah',
      category: 'DRAINAGE_MAINTENANCE',
      coreInstruction: 'Angkat sampah daun dan plastik yang menyumbat grill saluran depan rumah secara mandiri.',
      safetyInstruction: 'DILARANG masuk ke dalam gorong-gorong atau mendekati arus air deras. Gunakan sarung tangan dan alat bantu garuk.',
      estimatedDurationMinutes: 45,
    );

    final templateTanam = TaskTemplateSnapshot(
      templateId: 'penanaman_pohon_resapan',
      version: 1,
      title: 'Tanam Bibit Pohon Resapan Lingkungan',
      category: 'GREENING',
      coreInstruction: 'Tanam bibit pohon pelindung/resapan di halaman atau area resapan yang telah ditentukan RT.',
      safetyInstruction: 'Pastikan tidak menggali dekat instalasi pipa air atau kabel listrik tanah.',
      estimatedDurationMinutes: 60,
    );

    // 2. Kampanye Tugas Aktif RT
    final campaign1 = TaskCampaignRecord(
      campaignId: 'camp-demo-01',
      rtId: 'rt-01-demo',
      templateSnapshot: templateTasSiaga,
      deadline: now.add(const Duration(hours: 18)),
      status: 'ACTIVE',
      createdAt: now.subtract(const Duration(hours: 3)),
      activatedAt: now.subtract(const Duration(hours: 2)),
    );

    final campaign2 = TaskCampaignRecord(
      campaignId: 'camp-demo-02',
      rtId: 'rt-01-demo',
      templateSnapshot: templateSaluran,
      deadline: now.add(const Duration(hours: 24)),
      status: 'ACTIVE',
      createdAt: now.subtract(const Duration(hours: 2)),
      activatedAt: now.subtract(const Duration(hours: 1)),
    );

    final campaign3 = TaskCampaignRecord(
      campaignId: 'camp-demo-03',
      rtId: 'rt-01-demo',
      templateSnapshot: templateTanam,
      deadline: now.add(const Duration(hours: 48)),
      status: 'ACTIVE',
      createdAt: now.subtract(const Duration(hours: 4)),
      activatedAt: now.subtract(const Duration(hours: 3)),
    );

    _campaigns.addAll([campaign1, campaign2, campaign3]);

    // 3. Tugas Aktif untuk Warga
    _residentTasks.add(
      ResidentTaskRecord(
        taskId: campaign1.campaignId,
        rtId: 'rt-01-demo',
        templateSnapshot: templateTasSiaga,
        deadline: campaign1.deadline,
        status: 'ACTIVE',
        participation: ParticipationState.joined,
        completion: CompletionState.pendingRtVerification,
        completionNote: 'Tas siaga siap di lantai 2.',
      ),
    );

    _residentTasks.add(
      ResidentTaskRecord(
        taskId: campaign2.campaignId,
        rtId: 'rt-01-demo',
        templateSnapshot: templateSaluran,
        deadline: campaign2.deadline,
        status: 'ACTIVE',
        participation: ParticipationState.unresponded,
        completion: CompletionState.notSubmitted,
      ),
    );

    _residentTasks.add(
      ResidentTaskRecord(
        taskId: campaign3.campaignId,
        rtId: 'rt-01-demo',
        templateSnapshot: templateTanam,
        deadline: campaign3.deadline,
        status: 'ACTIVE',
        participation: ParticipationState.joined,
        completion: CompletionState.notSubmitted,
      ),
    );

    // 4. Antrean Verifikasi untuk Operator RT
    _pendingVerifications.add(
      TaskVerificationRecord(
        responseId: 'resp-budi-01',
        taskId: campaign1.campaignId,
        taskTitle: templateTasSiaga.title,
        nickname: 'Budi (No. 08)',
        submittedAt: now.subtract(const Duration(minutes: 25)),
        completionNote:
            'Tas siaga dan berkas penting sudah diamankan di lantai 2.',
      ),
    );

    // 5. Usulan Warga Pre-seeded
    _proposals.add(
      ResidentProposalRecord(
        proposalId: 'a1b2c3d4e5f60718293a4b5c6d7e8f901a2b3c4d',
        title: 'Usul Peninggian Tanggul Selokan Gang 2',
        description:
            'Genangan sering meluap saat hujan deras lebih dari 1 jam.',
        category: ResidentProposalCategory.environmentalCleanup,
        state: 'SUBMITTED',
        submittedAt: now.subtract(const Duration(hours: 5)),
      ),
    );

    _proposals.add(
      ResidentProposalRecord(
        proposalId: 'b2c3d4e5f60718293a4b5c6d7e8f901a2b3c4d5e',
        title: 'Sampah Menumpuk di Jembatan Utama',
        description: 'Tumpukan batang kayu besar tersangkut di tiang jembatan.',
        category: ResidentProposalCategory.safeVisualInspection,
        state: 'NEEDS_OFFICIAL_REPORT',
        submittedAt: now.subtract(const Duration(days: 1)),
        reviewedAt: now.subtract(const Duration(hours: 12)),
      ),
    );

    // 6. Titik Pohon Komunitas RT (Geohash 7 sekitar Tulungagung / Jawa Timur)
    _trees.add(
      CommunityTreeItem(
        treePointId: 'tree-01',
        speciesHint: 'Pohon Trembesi (Peneduh)',
        submitterNickname: 'Pak Joko',
        isAnonymous: false,
        coarseLocation: const CoarseLocation(
          cellId: 'qqwvt7u',
          approximateLat: -8.0645,
          approximateLng: 111.9015,
        ),
        plantedAt: now.subtract(const Duration(days: 12)),
        hasEvidencePhoto: true,
      ),
    );

    _trees.add(
      CommunityTreeItem(
        treePointId: 'tree-02',
        speciesHint: 'Pohon Ketapang Kencana',
        submitterNickname: 'Ibu Ratna',
        isAnonymous: false,
        coarseLocation: const CoarseLocation(
          cellId: 'qqwvt7v',
          approximateLat: -8.0628,
          approximateLng: 111.9032,
        ),
        plantedAt: now.subtract(const Duration(days: 8)),
        hasEvidencePhoto: false,
      ),
    );

    _trees.add(
      CommunityTreeItem(
        treePointId: 'tree-03',
        speciesHint: 'Pohon Pucuk Merah Resapan',
        submitterNickname: 'Warga RT 01',
        isAnonymous: true,
        coarseLocation: const CoarseLocation(
          cellId: 'qqwvt7w',
          approximateLat: -8.0660,
          approximateLng: 111.9002,
        ),
        plantedAt: now.subtract(const Duration(days: 3)),
        hasEvidencePhoto: true,
      ),
    );

    // 7. Proxy Residents (Warga Rentan)
    _proxyResidents.add(
      ProxyResidentRecord(
        residentId: '550e8400-e29b-41d4-a716-446655440001',
        nickname: 'Mbah Supardi (Lansia)',
        houseNumber: '12',
        needsAssistance: true,
        createdAt: now.subtract(const Duration(days: 20)),
      ),
    );

    _proxyResidents.add(
      ProxyResidentRecord(
        residentId: '550e8400-e29b-41d4-a716-446655440002',
        nickname: 'Ibu Aminah (Disabilitas Fisik)',
        houseNumber: '05A',
        needsAssistance: true,
        createdAt: now.subtract(const Duration(days: 15)),
      ),
    );
  }

  late final _weather = _DemoWeatherBoundary();

  // --- Auth Boundary ---
  OperatorAuthBoundary createAuthBoundary() => _DemoOperatorAuthBoundary(this);

  // --- Resident Session Boundary ---
  ResidentSessionBoundary createSessionBoundary() =>
      _DemoResidentSessionBoundary(this);

  // --- Task Campaign Boundary ---
  TaskCampaignBoundary createTaskBoundary() => _DemoTaskCampaignBoundary(this);

  // --- Task Response Boundary ---
  TaskResponseBoundary createResponseBoundary() =>
      _DemoTaskResponseBoundary(this);

  // --- Task Evidence Boundary ---
  TaskEvidenceBoundary createEvidenceBoundary() => _DemoEvidenceBoundary();

  // --- Resident Proposal Boundary ---
  ResidentProposalBoundary createProposalBoundary() =>
      _DemoResidentProposalBoundary(this);

  // --- Tree Point Boundary ---
  TreePointBoundary createTreeBoundary() => _DemoTreePointBoundary(this);

  // --- Emergency Directory Boundary ---
  EmergencyDirectoryBoundary createEmergencyBoundary() =>
      _DemoEmergencyDirectoryBoundary();

  // --- Weather Suggestion Boundary ---
  WeatherSuggestionBoundary createWeatherBoundary() => _weather;

  // --- Weather Snapshot Boundary ---
  WeatherSnapshotBoundary createWeatherSnapshotBoundary() => _weather;

  // --- Proxy Resident Boundary ---
  ProxyResidentBoundary createProxyBoundary() =>
      _DemoProxyResidentBoundary(this);

  // --- Assistance Volunteer Boundary ---
  AssistanceVolunteerBoundary createVolunteerBoundary() =>
      _DemoAssistanceVolunteerBoundary();
}

// -----------------------------------------------------------------------------
// Implementations
// -----------------------------------------------------------------------------

final class _DemoOperatorAuthBoundary implements OperatorAuthBoundary {
  _DemoOperatorAuthBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  }) async {
    final profile = OperatorProfile(
      uid: 'op-demo-rt01',
      communityId: 'rt-01-demo',
      displayName: 'Ketua RT 01 Kedungwaru',
      role: OperatorRole.ketuaRtRw,
      rtLabel: 'RT 01 / RW 02 Kedungwaru',
      communityName: 'Demo RT 01 / RW 02 Kedungwaru',
    );
    engine.activeOperator = profile;
    return Result.ok(profile);
  }

  @override
  Future<Result<OperatorProfile>> restoreCurrentSession() async {
    if (engine.activeOperator != null) {
      return Result.ok(engine.activeOperator!);
    }
    return const Result.err(
      AuthError(message: 'Belum ada sesi operator tersimpan.'),
    );
  }

  @override
  Future<void> signOut() async {
    engine.activeOperator = null;
  }
}

final class _DemoResidentSessionBoundary implements ResidentSessionBoundary {
  _DemoResidentSessionBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<ResidentSessionGrant> createSession({
    required String joinCode,
    required String nickname,
    required String requestId,
  }) async {
    final session = ResidentSession(
      residentId: 'res-budi-01',
      communityId: 'rt-01-demo',
      communityName: 'Demo RT 01 / RW 02 Kedungwaru',
      rtLabel: 'RT 01 / RW 02 Kedungwaru',
      nickname: nickname.trim().isNotEmpty ? nickname.trim() : 'Budi',
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    engine.activeResident = session;
    return ResidentSessionGrant(
      session: session,
      sessionToken: 'demo-token-res-budi-01',
    );
  }

  @override
  Future<ResidentSession> validateSession(String sessionToken) async {
    return engine.activeResident ??
        ResidentSession(
          residentId: 'res-budi-01',
          communityId: 'rt-01-demo',
          communityName: 'Demo RT 01 / RW 02 Kedungwaru',
          rtLabel: 'RT 01 / RW 02 Kedungwaru',
          nickname: 'Budi',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        );
  }

  @override
  Future<void> revokeSession(String sessionToken) async {
    engine.activeResident = null;
  }

  @override
  Future<void> deleteOwnResidentData({
    required String sessionToken,
    required String residentId,
    required String communityId,
  }) async {
    engine.activeResident = null;
  }
}

final class _DemoTaskCampaignBoundary implements TaskCampaignBoundary {
  _DemoTaskCampaignBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<List<TaskTemplate>> listApprovedTemplates() async => [
    TaskTemplate(
      id: 'tas_siaga_keluarga',
      version: 1,
      title: 'Siapkan Tas Siaga & Dokumen Penting',
      category: 'HOUSEHOLD_PREPARATION',
      coreInstruction: 'Kumpulkan dokumen KK, KTP, ijazah, surat berharga, obat pribadi, senter, dan pakaian ganti ke dalam tas tahan air.',
      safetyInstruction: 'Jangan meletakkan dokumen berharga di lantai dasar. Letakkan tas di area mudah dijangkau saat darurat.',
      enabled: true,
      estimatedDurationMinutes: 30,
    ),
    TaskTemplate(
      id: 'bersihkan_saluran_depan',
      version: 1,
      title: 'Pembersihan Saluran Air Depan Rumah',
      category: 'DRAINAGE_MAINTENANCE',
      coreInstruction: 'Angkat sampah daun dan plastik yang menyumbat grill saluran depan rumah secara mandiri.',
      safetyInstruction: 'DILARANG masuk ke dalam gorong-gorong atau mendekati arus air deras. Gunakan sarung tangan dan alat bantu garuk.',
      enabled: true,
      estimatedDurationMinutes: 45,
    ),
    TaskTemplate(
      id: 'penanaman_pohon_resapan',
      version: 1,
      title: 'Tanam Bibit Pohon Resapan Lingkungan',
      category: 'GREENING',
      coreInstruction: 'Tanam bibit pohon pelindung/resapan di halaman atau area resapan yang telah ditentukan RT.',
      safetyInstruction: 'Pastikan tidak menggali dekat instalasi pipa air atau kabel listrik tanah.',
      enabled: true,
      estimatedDurationMinutes: 60,
    ),
  ];

  @override
  Future<TaskCampaignRecord> createDraft({
    required TaskTemplate template,
    required DateTime deadline,
    required String? locationReference,
    required String requestId,
    String? customInstruction,
  }) async {
    final record = TaskCampaignRecord(
      campaignId: 'camp-demo-${DateTime.now().millisecondsSinceEpoch}',
      rtId: 'rt-01-demo',
      templateSnapshot: TaskTemplateSnapshot(
        templateId: template.id,
        version: template.version,
        title: template.title,
        category: template.category,
        coreInstruction: customInstruction ?? template.coreInstruction,
        safetyInstruction: template.safetyInstruction,
        estimatedDurationMinutes: template.estimatedDurationMinutes,
      ),
      deadline: deadline,
      status: 'DRAFT',
      createdAt: DateTime.now(),
      locationReference: locationReference,
      activatedAt: null,
    );
    engine._campaigns.insert(0, record);
    return record;
  }

  @override
  Future<TaskCampaignRecord> activateCampaign({
    required String campaignId,
    required String commandId,
  }) async {
    final index = engine._campaigns.indexWhere(
      (c) => c.campaignId == campaignId,
    );
    if (index != -1) {
      final old = engine._campaigns[index];
      final updated = TaskCampaignRecord(
        campaignId: campaignId,
        rtId: old.rtId,
        templateSnapshot: old.templateSnapshot,
        deadline: old.deadline,
        status: 'ACTIVE',
        createdAt: old.createdAt,
        locationReference: old.locationReference,
        activatedAt: DateTime.now(),
      );
      engine._campaigns[index] = updated;
      return updated;
    }
    throw StateError('Campaign not found');
  }
}

final class _DemoTaskResponseBoundary implements TaskResponseBoundary {
  _DemoTaskResponseBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<ResidentTaskList> listResidentActiveTasks({
    required String sessionToken,
  }) async => ResidentTaskList(items: engine._residentTasks, isPartial: false);

  @override
  Future<TaskResponseRecord> recordResidentTaskResponse({
    required String sessionToken,
    required String taskId,
    required ParticipationChoice choice,
    required String commandId,
  }) async {
    final state = choice == ParticipationChoice.join
        ? ParticipationState.joined
        : ParticipationState.declined;
    return TaskResponseRecord(
      taskId: taskId,
      participation: state,
      completion: CompletionState.notSubmitted,
    );
  }

  @override
  Future<TaskResponseRecord> submitTaskCompletion({
    required String sessionToken,
    required String taskId,
    required String? note,
    required String commandId,
    String? evidenceId,
  }) async {
    return TaskResponseRecord(
      taskId: taskId,
      participation: ParticipationState.joined,
      completion: CompletionState.pendingRtVerification,
      completionNote: note,
      evidenceId: evidenceId,
    );
  }

  @override
  Future<TaskVerificationQueue> listPendingVerifications() async =>
      TaskVerificationQueue(
        items: engine._pendingVerifications,
        isPartial: false,
      );

  @override
  Future<TaskResponseRecord> verifyTaskCompletion({
    required String responseId,
    required String commandId,
  }) async {
    engine._pendingVerifications.removeWhere((v) => v.responseId == responseId);
    return const TaskResponseRecord(
      taskId: 'camp-demo-01',
      participation: ParticipationState.joined,
      completion: CompletionState.verifiedComplete,
    );
  }

  @override
  Future<TaskResponseRecap> getResponseRecap({required String taskId}) async =>
      TaskResponseRecap(
        taskId: taskId,
        rtId: 'rt-01-demo',
        recordedResponseCount: 15,
        joinedCount: 12,
        declinedCount: 3,
        pendingVerificationCount: 1,
        verifiedCompleteCount: 11,
        isPartial: false,
        taskTitle: 'Siapkan Tas Siaga & Dokumen Penting',
      );
}

final class _DemoEvidenceBoundary implements TaskEvidenceBoundary {
  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {}

  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async =>
      'demo${DateTime.now().millisecondsSinceEpoch.toRadixString(16).padLeft(36, '0')}';

  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async => Uint8List(0);
}

final class _DemoResidentProposalBoundary implements ResidentProposalBoundary {
  _DemoResidentProposalBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<ResidentProposalRecord> submitResidentProposal({
    required String sessionToken,
    required String title,
    required String description,
    required ResidentProposalCategory category,
    required String? locationReference,
    required String requestId,
  }) async {
    final record = ResidentProposalRecord(
      proposalId: 'a1b2c3d4e5f60718293a4b5c6d7e8f901a2b3c4d',
      title: title,
      description: description,
      category: category,
      state: 'SUBMITTED',
      submittedAt: DateTime.now(),
      locationReference: locationReference,
    );
    engine._proposals.insert(0, record);
    return record;
  }

  @override
  Future<List<ResidentProposalRecord>> listMyProposals({
    required String sessionToken,
  }) async => engine._proposals;

  @override
  Future<ResidentProposalQueue> listResidentProposals() async =>
      ResidentProposalQueue(items: engine._proposals, isPartial: false);

  @override
  Future<ResidentProposalRecord> reviewResidentProposal({
    required String proposalId,
    required String decision,
    required String commandId,
  }) async {
    final index = engine._proposals.indexWhere(
      (p) => p.proposalId == proposalId,
    );
    if (index != -1) {
      final old = engine._proposals[index];
      final updated = ResidentProposalRecord(
        proposalId: old.proposalId,
        title: old.title,
        description: old.description,
        category: old.category,
        state: decision,
        submittedAt: old.submittedAt,
        locationReference: old.locationReference,
        submitterNickname: old.submitterNickname,
        reviewedAt: DateTime.now(),
      );
      engine._proposals[index] = updated;
      return updated;
    }
    throw StateError('Proposal not found');
  }

  @override
  Future<ResidentProposalDraftMapping> mapResidentProposalToDraft({
    required String proposalId,
    required String templateId,
    required int version,
    required DateTime deadline,
    required String? locationReference,
    required String commandId,
  }) async {
    return ResidentProposalDraftMapping(
      proposalId: proposalId,
      state: 'MAPPED_TO_SAFE_TEMPLATE',
      reviewedAt: DateTime.now(),
      campaign: engine._campaigns.first,
    );
  }
}

final class _DemoTreePointBoundary implements TreePointBoundary {
  _DemoTreePointBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<TreePointSubmissionResult> submitTreePoint({
    required String sessionToken,
    required String taskId,
    String? speciesHint,
    required double exactLat,
    required double exactLng,
    required double accuracyMeters,
    required bool isMocked,
    String? evidenceId,
    required String commandId,
  }) async {
    final newItem = CommunityTreeItem(
      treePointId: 'tree-demo-${DateTime.now().millisecondsSinceEpoch}',
      speciesHint: speciesHint ?? 'Pohon Resapan Lingkungan',
      submitterNickname: engine.activeResident?.nickname ?? 'Warga RT',
      isAnonymous: false,
      coarseLocation: CoarseLocation(
        cellId: 'qqwvt7x',
        approximateLat: exactLat,
        approximateLng: exactLng,
      ),
      plantedAt: DateTime.now(),
      hasEvidencePhoto: evidenceId != null,
    );
    engine._trees.insert(0, newItem);
    return TreePointSubmissionResult(
      treePointId: newItem.treePointId,
      status: TreePointStatus.verified,
      coarseLocation: newItem.coarseLocation,
      submittedAt: DateTime.now(),
    );
  }

  @override
  Future<CommunityTreeMap> listCommunityTreeMap({String? sessionToken}) async =>
      CommunityTreeMap(
        items: engine._trees,
        totalVerifiedTrees: engine._trees.length,
      );

  @override
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
    required String commandId,
  }) async => TreePointVerificationResult(
    treePointId: treePointId,
    status: decision == TreePointDecision.approve
        ? TreePointStatus.verified
        : TreePointStatus.rejected,
    verifiedAt: DateTime.now(),
  );

  @override
  Future<void> deleteTreePoint({
    required String treePointId,
    String? reason,
  }) async {
    engine._trees.removeWhere((t) => t.treePointId == treePointId);
  }
}

final class _DemoEmergencyDirectoryBoundary
    implements EmergencyDirectoryBoundary {
  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) async => EmergencyDirectoryResponse.fromWire({
    'state': 'ACTIVE',
    'version': 1,
    'lastVerifiedAt': DateTime.now().toUtc().toIso8601String(),
    'emergencyContacts': [
      {
        'serviceName': 'Pemadam Kebakaran & Evakuasi',
        'telephoneNumber': '113',
        'isOfficial': true,
      },
      {
        'serviceName': 'BPBD Kabupaten Tulungagung',
        'telephoneNumber': '0355-327799',
        'isOfficial': true,
      },
      {
        'serviceName': 'Puskesmas Kedungwaru',
        'telephoneNumber': '0355-321456',
        'isOfficial': true,
      },
      {
        'serviceName': 'Polsek Kedungwaru',
        'telephoneNumber': '0355-321110',
        'isOfficial': true,
      },
      {
        'serviceName': 'Ambulans PMI',
        'telephoneNumber': '118',
        'isOfficial': true,
      },
    ],
    'assemblyPoints': [
      {'name': 'Balai RW 02 Kedungwaru (Posko Utama)', 'isVerified': true},
      {
        'name': 'Lapangan Desa Kedungwaru (Titik Kumpul Terbuka)',
        'isVerified': true,
      },
    ],
    'officialReportChannels': [
      {
        'name': 'Kanal Laporan Resmi Kelurahan & Siaga Bencana',
        'url': 'https://tulungagung.go.id',
      },
    ],
  });
}

final class _DemoWeatherBoundary
    implements WeatherSuggestionBoundary, WeatherSnapshotBoundary {
  @override
  Future<List<WeatherSuggestion>> listWeatherSuggestions() async => [
    WeatherSuggestion(
      id: 'sug-bmkg-01',
      sourceSnapshotId: 'snap-01',
      ruleId: 'RULE_HEAVY_RAIN',
      recommendedTemplateIds: const [
        'tas_siaga_keluarga',
        'bersihkan_saluran_depan',
      ],
      createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
      explanation: 'BMKG mendeteksi potensi hujan sedang hingga lebat disertai kilat/petir di wilayah Tulungagung sore ini.',
    ),
  ];

  @override
  Future<void> ignoreWeatherSuggestion({required String suggestionId}) async {}

  @override
  Future<WeatherSnapshot?> getForOperator() async => _demoSnapshot();

  @override
  Future<WeatherSnapshot?> getForResident({
    required String sessionToken,
  }) async => _demoSnapshot();

  WeatherSnapshot _demoSnapshot() => WeatherSnapshot(
    id: 'snap-01',
    communityId: 'rt-01-demo',
    sourceUpdatedAt: DateTime.now().subtract(const Duration(minutes: 20)),
    fetchedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    rainfallMm: 35.5,
  );
}

final class _DemoProxyResidentBoundary implements ProxyResidentBoundary {
  _DemoProxyResidentBoundary(this.engine);
  final StandaloneDemoEngine engine;

  @override
  Future<String> cancelPendingProxyResidentCreate({
    required String requestId,
  }) async => 'CANCELLED';

  @override
  Future<ProxyResidentRecord> createProxyResident({
    required String nickname,
    required String? houseNumber,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String requestId,
  }) async {
    final record = ProxyResidentRecord(
      residentId: '550e8400-e29b-41d4-a716-446655440003',
      nickname: nickname,
      houseNumber: houseNumber,
      needsAssistance: needsAssistance,
      createdAt: DateTime.now(),
    );
    engine._proxyResidents.add(record);
    return record;
  }

  @override
  Future<ProxyResidentList> listProxyResidents() async =>
      ProxyResidentList(residents: engine._proxyResidents, isPartial: false);

  @override
  Future<VolunteerHelperList> listVolunteerHelpers() async =>
      VolunteerHelperList(items: const [], isPartial: false);

  @override
  Future<HelperAssignmentResult> createHelperAssignment({
    required String residentId,
    required String helperResidentId,
    required String commandId,
  }) async =>
      const HelperAssignmentResult(assignmentId: 'a-1', state: 'OFFERED');

  @override
  Future<ProxyTaskStatusRecord> getProxyTaskStatus({
    required String residentId,
    required String taskId,
  }) async => const ProxyTaskStatusRecord(
    taskId: 'camp-demo-01',
    participationState: 'JOINED',
    completionState: 'NOT_SUBMITTED',
  );

  @override
  Future<ProxyTaskStatusRecord> updateProxyTaskStatus({
    required String residentId,
    required String taskId,
    required String participationState,
    required bool completionReported,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => ProxyTaskStatusRecord(
    taskId: taskId,
    participationState: participationState,
    completionState: completionReported ? 'VERIFIED' : 'NOT_SUBMITTED',
  );

  @override
  Future<ProxyAssistanceUpdate> updateProxyAssistance({
    required String residentId,
    required bool needsAssistance,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async {
    final index = engine._proxyResidents.indexWhere(
      (p) => p.residentId == residentId,
    );
    if (index != -1) {
      final old = engine._proxyResidents[index];
      engine._proxyResidents[index] = ProxyResidentRecord(
        residentId: old.residentId,
        nickname: old.nickname,
        houseNumber: old.houseNumber,
        needsAssistance: needsAssistance,
        createdAt: old.createdAt,
      );
    }
    return ProxyAssistanceUpdate(
      residentId: residentId,
      needsAssistance: needsAssistance,
    );
  }

  @override
  Future<void> deleteResidentData({
    required String residentId,
    required bool residentRequestConfirmed,
    required bool identityVerificationConfirmed,
    required String commandId,
  }) async {
    engine._proxyResidents.removeWhere((p) => p.residentId == residentId);
  }
}

final class _DemoAssistanceVolunteerBoundary
    implements AssistanceVolunteerBoundary {
  @override
  Future<ResidentVolunteerData> getVolunteerData({
    required String sessionToken,
  }) async => ResidentVolunteerData(
    willingToHelp: true,
    assignments: const [],
    isPartial: false,
  );

  @override
  Future<bool> updateVolunteerConsent({
    required String sessionToken,
    required bool willingToHelp,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => willingToHelp;

  @override
  Future<HelperAssignmentResult> respondToHelperAssignment({
    required String sessionToken,
    required String assignmentId,
    required String decision,
    required bool residentConsentConfirmed,
    required String commandId,
  }) async => HelperAssignmentResult(
    assignmentId: assignmentId,
    state: decision == 'ACCEPT' ? 'ACCEPTED' : 'DECLINED',
  );
}
