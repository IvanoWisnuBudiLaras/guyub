// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../auth/application/resident_session.dart';
import '../../auth/application/resident_session_vault.dart';
import 'emergency_directory_cache.dart';
import 'emergency_directory.dart';
import 'emergency_directory_boundary.dart';

enum EmergencyDirectoryViewStatus {
  loading,
  active,
  disabled,
  unconfigured,
  unavailable,
}

/// Presentation-ready state. `isOffline` means the visible data is a local
/// fallback, even if the last callable response was reachable but unusable.
final class EmergencyDirectoryViewState {
  const EmergencyDirectoryViewState({
    this.status = EmergencyDirectoryViewStatus.loading,
    this.snapshot,
    this.isRefreshing = false,
    this.isOffline = false,
    this.hasConflict = false,
  });

  final EmergencyDirectoryViewStatus status;
  final EmergencyDirectoryCacheSnapshot? snapshot;
  final bool isRefreshing;
  final bool isOffline;
  final bool hasConflict;
}

/// Loads a local directory before refreshing through the secure resident token.
/// The screen receives a [ResidentSession], never the bearer token.
final class EmergencyDirectoryController extends ChangeNotifier {
  EmergencyDirectoryController({
    required EmergencyDirectoryBoundary boundary,
    required EmergencyDirectoryCacheStore cache,
    required ResidentSessionVault vault,
    DateTime Function()? clock,
  }) : _boundary = boundary,
       _cache = cache,
       _vault = vault,
       _clock = clock ?? DateTime.now;

  final EmergencyDirectoryBoundary _boundary;
  final EmergencyDirectoryCacheStore _cache;
  final ResidentSessionVault _vault;
  final DateTime Function() _clock;
  ResidentSession? _session;
  int _generation = 0;
  bool _disposed = false;

  EmergencyDirectoryViewState _state = const EmergencyDirectoryViewState();
  EmergencyDirectoryViewState get state => _state;

  /// Reads the same RT/resident cache first, then attempts the callable refresh.
  Future<void> load({required ResidentSession session}) async {
    final generation = ++_generation;
    _session = session;
    _publish(
      EmergencyDirectoryViewState(
        status: EmergencyDirectoryViewStatus.loading,
        isRefreshing: true,
      ),
    );

    EmergencyDirectoryCacheSnapshot? cached;
    try {
      cached = await _cache.readSnapshotForSession(session: session);
    } catch (_) {
      // A local-store failure must not block the online refresh attempt.
    }
    if (generation != _generation) return;
    _publish(
      EmergencyDirectoryViewState(
        status: cached == null
            ? EmergencyDirectoryViewStatus.loading
            : EmergencyDirectoryViewStatus.active,
        snapshot: cached,
        isRefreshing: true,
        isOffline: cached != null,
      ),
    );
    await _refreshFor(session, generation);
  }

  /// Loads the latest verified local copy without requiring a signed-in resident.
  /// This keeps Darurat reachable from role selection after sign-out/restart.
  Future<void> loadLatest() async {
    final generation = ++_generation;
    _session = null;
    _publish(
      const EmergencyDirectoryViewState(
        status: EmergencyDirectoryViewStatus.loading,
        isRefreshing: true,
        isOffline: true,
      ),
    );
    EmergencyDirectoryCacheSnapshot? snapshot;
    try {
      snapshot = await _cache.readLatestSnapshot();
    } catch (_) {
      // The unauthenticated emergency screen remains available if storage fails.
    }
    if (generation != _generation) return;
    _publish(
      EmergencyDirectoryViewState(
        status: snapshot == null
            ? EmergencyDirectoryViewStatus.unavailable
            : EmergencyDirectoryViewStatus.active,
        snapshot: snapshot,
        isOffline: true,
      ),
    );
  }

  /// Refreshes online for a resident session, or rereads the public local copy
  /// when the screen is opened without an authenticated resident session.
  Future<void> refresh() async {
    final session = _session;
    if (session == null) {
      await loadLatest();
      return;
    }
    await _refreshFor(session, _generation);
  }

  Future<void> _refreshFor(ResidentSession session, int generation) async {
    final existing = _state.snapshot;
    _publish(
      EmergencyDirectoryViewState(
        status: existing == null
            ? EmergencyDirectoryViewStatus.loading
            : EmergencyDirectoryViewStatus.active,
        snapshot: existing,
        isRefreshing: true,
        isOffline: _state.isOffline,
        hasConflict: _state.hasConflict,
      ),
    );

    try {
      final token = await _vault.read();
      if (token == null || token.isEmpty) {
        throw StateError('No secure resident session token is available.');
      }
      final response = await _boundary.getEmergencyDirectory(
        sessionToken: token,
      );
      final result = await _cache.applyResponse(
        session: session,
        response: response,
        syncedAt: _clock().toUtc(),
      );
      if (generation != _generation) return;
      final nextSnapshot = result.snapshot;
      final nextStatus = nextSnapshot != null
          ? EmergencyDirectoryViewStatus.active
          : switch (response.status) {
              EmergencyDirectoryStatus.active =>
                EmergencyDirectoryViewStatus.unavailable,
              EmergencyDirectoryStatus.disabled =>
                EmergencyDirectoryViewStatus.disabled,
              EmergencyDirectoryStatus.unconfigured =>
                EmergencyDirectoryViewStatus.unconfigured,
            };
      _publish(
        EmergencyDirectoryViewState(
          status: nextStatus,
          snapshot: nextSnapshot,
          isRefreshing: false,
          isOffline: result.usedCachedData,
          hasConflict: result.hasConflict,
        ),
      );
    } catch (_) {
      if (generation != _generation) return;
      var fallback = _state.snapshot;
      if (fallback == null) {
        try {
          fallback = await _cache.readSnapshotForSession(session: session);
        } catch (_) {
          // The screen falls through to an unavailable message below.
        }
      }
      if (generation != _generation) return;
      _publish(
        EmergencyDirectoryViewState(
          status: fallback == null
              ? EmergencyDirectoryViewStatus.unavailable
              : EmergencyDirectoryViewStatus.active,
          snapshot: fallback,
          isRefreshing: false,
          isOffline: fallback != null,
        ),
      );
    }
  }

  void _publish(EmergencyDirectoryViewState next) {
    _state = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
