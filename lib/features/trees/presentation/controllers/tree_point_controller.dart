import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../application/device_location_service.dart';
import '../../application/tree_point_boundary.dart';
import '../../domain/tree_point.dart';
import '../../../evidence/application/evidence_image_sanitizer.dart';
import '../../../evidence/application/task_evidence_boundary.dart';

/// Controller untuk alur penanaman, pemetaan, dan verifikasi titik pohon.
final class TreePointController {
  TreePointController({
    required this.boundary,
    required this.locationService,
    this.evidenceBoundary,
    this.readSessionToken,
    String Function()? commandIdFactory,
  }) : _commandIdFactory = commandIdFactory ?? _newCommandId;

  final TreePointBoundary boundary;
  final DeviceLocationService locationService;
  final TaskEvidenceBoundary? evidenceBoundary;
  final Future<String?> Function()? readSessionToken;
  final String Function() _commandIdFactory;

  /// Memeriksa izin lokasi GPS.
  Future<bool> checkLocationPermission() => locationService.hasPermission();

  /// Meminta izin lokasi GPS runtime.
  Future<bool> requestLocationPermission() =>
      locationService.requestPermission();

  /// Membaca sensor GPS terkini dari perangkat.
  Future<DeviceGpsReading> getCurrentGpsReading() =>
      locationService.getCurrentReading();

  /// Mengirimkan titik pohon baru dari warga.
  Future<TreePointSubmissionResult> submitTreePoint({
    String? sessionToken,
    required String taskId,
    String? speciesHint,
    required DeviceGpsReading reading,
    Uint8List? rawImageBytes,
  }) async {
    final token = sessionToken ?? await readSessionToken?.call();
    if (token == null || token.isEmpty) {
      throw const TreePointException(
        'Sesi warga tidak aktif atau kedaluwarsa.',
      );
    }
    // 1. Validasi GPS
    if (reading.isMocked) {
      throw const TreePointMockLocationException(
        'Lokasi palsu (mock location) terdeteksi. Gunakan lokasi GPS asli.',
      );
    }
    if (!reading.isAcceptableAccuracy) {
      throw TreePointAccuracyException(
        'Akurasi GPS ±${reading.accuracyMeters.toStringAsFixed(1)}m melebihi batas '
        'maksimal (${DeviceGpsReading.maxAcceptableAccuracyMeters.toInt()}m). '
        'Harap tunggu sinyal GPS lebih kuat atau berpindah ke ruang terbuka.',
      );
    }

    // 2. Sanitasi Jenis Pohon
    final sanitizedHint = TreePointValidation.validateSpeciesHint(speciesHint);

    final commandId = _commandIdFactory();
    String? evidenceId;

    // 3. Sanitasi & Upload Foto Bukti (jika ada)
    if (rawImageBytes != null && rawImageBytes.isNotEmpty) {
      final sanitized = EvidenceImageSanitizer.sanitize(rawImageBytes);
      final evBoundary = evidenceBoundary;
      if (evBoundary != null) {
        evidenceId = await evBoundary.uploadResidentTaskEvidence(
          sessionToken: token,
          taskId: taskId,
          requestId: commandId,
          sanitizedJpegBytes: sanitized.bytes,
        );
      }
    }

    // 4. Submit ke Backend Callable
    return boundary.submitTreePoint(
      sessionToken: token,
      taskId: taskId,
      speciesHint: sanitizedHint,
      exactLat: reading.latitude,
      exactLng: reading.longitude,
      accuracyMeters: reading.accuracyMeters,
      isMocked: reading.isMocked,
      evidenceId: evidenceId,
      commandId: commandId,
    );
  }

  /// Memuat daftar titik pohon terverifikasi pada peta komunitas.
  Future<CommunityTreeMap> loadCommunityMap({String? sessionToken}) async {
    final token = sessionToken ?? await readSessionToken?.call();
    return boundary.listCommunityTreeMap(sessionToken: token);
  }

  /// Verifikasi titik pohon oleh operator RT.
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
  }) {
    return boundary.verifyTreePoint(
      treePointId: treePointId,
      decision: decision,
      rejectionReason: rejectionReason,
      commandId: _commandIdFactory(),
    );
  }

  /// Menghapus titik pohon.
  Future<void> deleteTreePoint({required String treePointId, String? reason}) {
    return boundary.deleteTreePoint(treePointId: treePointId, reason: reason);
  }
}

String _newCommandId() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
