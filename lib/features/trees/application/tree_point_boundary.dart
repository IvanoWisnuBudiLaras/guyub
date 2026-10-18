import 'dart:core';

import '../domain/tree_point.dart';

enum TreePointDecision {
  approve,
  reject;

  String toWire() => this == TreePointDecision.approve ? 'APPROVE' : 'REJECT';
}

/// Hasil pengajuan titik pohon oleh warga.
final class TreePointSubmissionResult {
  const TreePointSubmissionResult({
    required this.treePointId,
    required this.status,
    required this.coarseLocation,
    required this.submittedAt,
  });

  final String treePointId;
  final TreePointStatus status;
  final CoarseLocation coarseLocation;
  final DateTime submittedAt;
}

/// Item titik pohon terverifikasi pada peta komunitas.
final class CommunityTreeItem {
  const CommunityTreeItem({
    required this.treePointId,
    this.speciesHint,
    required this.submitterNickname,
    this.isAnonymous = false,
    required this.coarseLocation,
    required this.plantedAt,
    this.hasEvidencePhoto = false,
  });

  final String treePointId;
  final String? speciesHint;
  final String submitterNickname;
  final bool isAnonymous;
  final CoarseLocation coarseLocation;
  final DateTime plantedAt;
  final bool hasEvidencePhoto;

  String get displaySubmitterName =>
      isAnonymous ? 'Pohon Warga (Anonim)' : submitterNickname;
}

/// Kumpulan titik pohon pada peta komunitas RT.
final class CommunityTreeMap {
  const CommunityTreeMap({
    required this.items,
    required this.totalVerifiedTrees,
    this.isCached = false,
  });

  final List<CommunityTreeItem> items;
  final int totalVerifiedTrees;
  final bool isCached;
}

/// Hasil verifikasi operator RT.
final class TreePointVerificationResult {
  const TreePointVerificationResult({
    required this.treePointId,
    required this.status,
    required this.verifiedAt,
  });

  final String treePointId;
  final TreePointStatus status;
  final DateTime verifiedAt;
}

/// Boundary interaksi dengan backend untuk fitur Pohon Guyub.
abstract interface class TreePointBoundary {
  /// Mengajukan titik pohon baru dari warga.
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
  });

  /// Mengambil daftar pohon komunitas terverifikasi untuk peta warga atau operator.
  Future<CommunityTreeMap> listCommunityTreeMap({String? sessionToken});

  /// Verifikasi oleh operator RT (menyetujui atau menolak).
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
    required String commandId,
  });

  /// Menghapus titik pohon.
  Future<void> deleteTreePoint({required String treePointId, String? reason});
}

/// Pengecualian jika akurasi GPS melebihi ambang batas aman (30 meter).
final class TreePointAccuracyException implements Exception {
  const TreePointAccuracyException([
    this.message = 'Akurasi GPS tidak memadai (maksimal 30 meter).',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Pengecualian jika perangkat terdeteksi menggunakan mock location (lokasi palsu).
final class TreePointMockLocationException implements Exception {
  const TreePointMockLocationException([
    this.message =
        'Lokasi palsu (mock location) terdeteksi. Pengajuan ditolak.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Pengecualian jika input teks mengandung PII atau teks berbahaya.
final class TreePointSanitizationException implements Exception {
  const TreePointSanitizationException([
    this.message = 'Input memuat informasi sensitif atau terlarang.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Pengecualian konflik status atau idempotency.
final class TreePointConflictException implements Exception {
  const TreePointConflictException([
    this.message = 'Titik pohon telah diproses atau dalam status tidak valid.',
  ]);
  final String message;
  @override
  String toString() => message;
}

/// Pengecualian umum titik pohon.
final class TreePointException implements Exception {
  const TreePointException(this.message);
  final String message;
  @override
  String toString() => message;
}
