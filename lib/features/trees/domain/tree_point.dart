import 'dart:core';

/// Status verifikasi titik pohon oleh RT.
enum TreePointStatus {
  pendingVerification,
  verified,
  rejected;

  static TreePointStatus fromWire(String raw) {
    switch (raw.toUpperCase()) {
      case 'VERIFIED':
        return TreePointStatus.verified;
      case 'REJECTED':
        return TreePointStatus.rejected;
      case 'PENDING_RT_VERIFICATION':
      default:
        return TreePointStatus.pendingVerification;
    }
  }

  String toWire() {
    switch (this) {
      case TreePointStatus.verified:
        return 'VERIFIED';
      case TreePointStatus.rejected:
        return 'REJECTED';
      case TreePointStatus.pendingVerification:
        return 'PENDING_RT_VERIFICATION';
    }
  }

  String get indonesianLabel {
    switch (this) {
      case TreePointStatus.verified:
        return 'Terverifikasi RT';
      case TreePointStatus.rejected:
        return 'Ditolak RT';
      case TreePointStatus.pendingVerification:
        return 'Menunggu Verifikasi RT';
    }
  }
}

/// Koordinat sel kasar (~153m x 153m, geohash level 7) yang aman dilihat publik RT.
final class CoarseLocation {
  const CoarseLocation({
    required this.cellId,
    required this.approximateLat,
    required this.approximateLng,
  });

  factory CoarseLocation.fromMap(Map<String, dynamic> map) {
    return CoarseLocation(
      cellId: (map['cellId'] ?? '').toString(),
      approximateLat: (map['approximateLat'] as num?)?.toDouble() ?? 0.0,
      approximateLng: (map['approximateLng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  final String cellId;
  final double approximateLat;
  final double approximateLng;

  Map<String, dynamic> toMap() => {
    'cellId': cellId,
    'approximateLat': approximateLat,
    'approximateLng': approximateLng,
  };
}

/// Entitas data titik pohon resapan Guyub.
final class TreePoint {
  const TreePoint({
    required this.treePointId,
    required this.rtId,
    required this.taskId,
    required this.residentId,
    required this.submitterNickname,
    this.speciesHint,
    required this.plantedAt,
    this.clientReportedAt,
    required this.status,
    this.rejectionReason,
    this.verifiedByOperatorUid,
    this.verifiedAt,
    required this.coarseLocation,
    this.evidenceId,
    this.evidenceExpiresAt,
    this.isAnonymous = false,
    this.hasEvidencePhoto = false,
  });

  final String treePointId;
  final String rtId;
  final String taskId;
  final String residentId;
  final String submitterNickname;
  final String? speciesHint;
  final DateTime plantedAt;
  final DateTime? clientReportedAt;
  final TreePointStatus status;
  final String? rejectionReason;
  final String? verifiedByOperatorUid;
  final DateTime? verifiedAt;
  final CoarseLocation coarseLocation;
  final String? evidenceId;
  final DateTime? evidenceExpiresAt;
  final bool isAnonymous;
  final bool hasEvidencePhoto;

  /// Label nama pemilik yang mematuhi invarian privasi (INV-05).
  String get displaySubmitterName =>
      isAnonymous ? 'Pohon Warga (Anonim)' : submitterNickname;
}

/// Pembacaan sensor GPS perangkat.
final class DeviceGpsReading {
  const DeviceGpsReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isMocked,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final bool isMocked;
  final DateTime timestamp;

  static const double maxAcceptableAccuracyMeters = 30.0;

  bool get isAcceptableAccuracy =>
      accuracyMeters > 0 && accuracyMeters <= maxAcceptableAccuracyMeters;

  bool get isValid =>
      !isMocked &&
      isAcceptableAccuracy &&
      latitude >= -90.0 &&
      latitude <= 90.0 &&
      longitude >= -180.0 &&
      longitude <= 180.0;
}

/// Validasi dan sanitasi input titik pohon.
final class TreePointValidation {
  const TreePointValidation._();

  static final RegExp _nikRegex = RegExp(r'\b\d{16}\b');
  static final RegExp _phoneRegex = RegExp(r'\b08\d{8,11}\b');
  static final RegExp _coordinateRegex = RegExp(
    r'[-+]?\d{1,2}\.\d{4,},\s*[-+]?\d{1,3}\.\d{4,}',
  );

  /// Memvalidasi jenis pohon dan menolak jika mengandung PII atau teks terlarang.
  static String? validateSpeciesHint(String? hint) {
    if (hint == null || hint.trim().isEmpty) return null;
    final trimmed = hint.trim();

    if (trimmed.length > 60) {
      throw const FormatException('Jenis pohon maksimal 60 karakter.');
    }
    if (_nikRegex.hasMatch(trimmed)) {
      throw const FormatException('Jenis pohon tidak boleh memuat NIK.');
    }
    if (_phoneRegex.hasMatch(trimmed)) {
      throw const FormatException(
        'Jenis pohon tidak boleh memuat nomor telepon.',
      );
    }
    if (_coordinateRegex.hasMatch(trimmed)) {
      throw const FormatException(
        'Jenis pohon tidak boleh memuat koordinat lokasi.',
      );
    }

    return trimmed;
  }
}
