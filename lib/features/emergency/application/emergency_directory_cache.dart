import '../../auth/application/resident_session.dart';
import 'emergency_directory.dart';

/// Application contract for reading and reconciling emergency directory caches.
abstract interface class EmergencyDirectoryCacheStore {
  Future<EmergencyDirectoryCacheSnapshot?> readSnapshot({
    required ResidentSession session,
  });

  Future<EmergencyDirectoryCacheSnapshot?> readSnapshotForSession({
    required ResidentSession session,
  });

  Future<EmergencyDirectoryCacheSnapshot?> readLatestSnapshot();

  Future<EmergencyDirectoryCacheSnapshot?> readLatestSnapshotForSession({
    required ResidentSession session,
  });

  Future<EmergencyDirectoryCacheResult> applyResponse({
    required ResidentSession session,
    required EmergencyDirectoryResponse response,
    required DateTime syncedAt,
  });
}

/// Locally synced active directory and RT display metadata.
final class EmergencyDirectoryCacheSnapshot {
  const EmergencyDirectoryCacheSnapshot({
    required this.directory,
    required this.syncedAt,
    required this.communityName,
    required this.rtLabel,
    required this.communityScopeHash,
  });

  final EmergencyDirectoryResponse directory;
  final DateTime syncedAt;
  final String communityName;
  final String rtLabel;

  /// One-way RT-scope hash used to avoid cross-RT use of the public latest copy.
  final String communityScopeHash;
}

final class EmergencyDirectoryCacheResult {
  const EmergencyDirectoryCacheResult({
    this.snapshot,
    this.usedCachedData = false,
    this.hasConflict = false,
    this.didWrite = false,
    this.didClear = false,
  });

  final EmergencyDirectoryCacheSnapshot? snapshot;
  final bool usedCachedData;
  final bool hasConflict;
  final bool didWrite;
  final bool didClear;
}
