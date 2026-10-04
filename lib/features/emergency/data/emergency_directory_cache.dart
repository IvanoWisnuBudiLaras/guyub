import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/database/local_store.dart';
import '../../auth/application/resident_session.dart';
import '../application/emergency_directory.dart';
import '../application/emergency_directory_cache.dart';

/// RT- and resident-scoped cache of the last valid ACTIVE directory.
///
/// The scope identifiers are used only to derive a hashed storage key. Cache
/// values contain the directory, local sync time, and RT display labels, but
/// never resident identifiers or the session bearer token.
final class EmergencyDirectoryCache implements EmergencyDirectoryCacheStore {
  EmergencyDirectoryCache(this._localStore);

  static const _cachePrefix = 'guyub.emergency-directory.v1.';
  static const _latestCacheKey = 'guyub.emergency-directory.latest.v1';
  static const _disabledPrefix = 'guyub.emergency-directory.disabled.v1.';
  final LocalStore _localStore;
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<EmergencyDirectoryCacheSnapshot?> readSnapshot({
    required ResidentSession session,
  }) async {
    final encoded = await _localStore.read(_cacheKey(session));
    if (encoded == null) return null;
    try {
      final envelope = _readMap(jsonDecode(encoded), 'cached directory');
      _expectKeys(envelope, const {
        'schemaVersion',
        'syncedAt',
        'communityName',
        'rtLabel',
        'communityScopeHash',
        'directory',
      });
      if (envelope['schemaVersion'] != 1) return null;
      final syncedAt = _date(envelope['syncedAt'], 'syncedAt');
      final communityName = _requiredText(
        envelope['communityName'],
        'communityName',
      );
      final rtLabel = _requiredText(envelope['rtLabel'], 'rtLabel');
      final scopeHash = _requiredText(
        envelope['communityScopeHash'],
        'communityScopeHash',
      );
      if (scopeHash != _communityScopeHash(session)) return null;
      final directory = EmergencyDirectoryResponse.fromWire(
        envelope['directory'],
      );
      if (directory.status != EmergencyDirectoryStatus.active) return null;
      final disabledRevision = await _readDisabledRevision(scopeHash);
      if (disabledRevision != null && disabledRevision >= directory.version!) {
        return null;
      }
      return EmergencyDirectoryCacheSnapshot(
        directory: directory,
        syncedAt: syncedAt,
        communityName: communityName,
        rtLabel: rtLabel,
        communityScopeHash: _communityScopeHash(session),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Returns a cache valid for [session]'s RT, preferring the higher data
  /// revision when this resident and the public latest copy both exist.
  @override
  Future<EmergencyDirectoryCacheSnapshot?> readSnapshotForSession({
    required ResidentSession session,
  }) async {
    final scoped = await readSnapshot(session: session);
    final latest = await readLatestSnapshotForSession(session: session);
    if (scoped == null) return latest;
    if (latest == null ||
        scoped.directory.version! >= latest.directory.version!) {
      return scoped;
    }
    return latest;
  }

  /// Reads the public latest copy only when it belongs to [session]'s RT.
  @override
  Future<EmergencyDirectoryCacheSnapshot?> readLatestSnapshotForSession({
    required ResidentSession session,
  }) async {
    final latest = await readLatestSnapshot();
    if (latest?.communityScopeHash != _communityScopeHash(session)) return null;
    return latest;
  }

  /// Reads the latest locally synchronized directory without requiring a
  /// resident session. Directory contacts and assembly points are public
  /// community information; the stored RT hash contains no resident ID.
  @override
  Future<EmergencyDirectoryCacheSnapshot?> readLatestSnapshot() async {
    final encoded = await _localStore.read(_latestCacheKey);
    if (encoded == null) return null;
    try {
      final envelope = _readMap(jsonDecode(encoded), 'latest cached directory');
      _expectKeys(envelope, const {
        'schemaVersion',
        'syncedAt',
        'communityName',
        'rtLabel',
        'communityScopeHash',
        'directory',
      });
      if (envelope['schemaVersion'] != 1) return null;
      final syncedAt = _date(envelope['syncedAt'], 'syncedAt');
      final communityName = _requiredText(
        envelope['communityName'],
        'communityName',
      );
      final rtLabel = _requiredText(envelope['rtLabel'], 'rtLabel');
      final scopeHash = _requiredText(
        envelope['communityScopeHash'],
        'communityScopeHash',
      );
      final directory = EmergencyDirectoryResponse.fromWire(
        envelope['directory'],
      );
      if (directory.status != EmergencyDirectoryStatus.active ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(scopeHash)) {
        return null;
      }
      final disabledRevision = await _readDisabledRevision(scopeHash);
      if (disabledRevision != null && disabledRevision >= directory.version!) {
        return null;
      }
      return EmergencyDirectoryCacheSnapshot(
        directory: directory,
        syncedAt: syncedAt,
        communityName: communityName,
        rtLabel: rtLabel,
        communityScopeHash: scopeHash,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  /// Applies a valid callable response without allowing old or conflicting
  /// revisions to replace an already cached directory.
  @override
  Future<EmergencyDirectoryCacheResult> applyResponse({
    required ResidentSession session,
    required EmergencyDirectoryResponse response,
    required DateTime syncedAt,
  }) => _serialize(() async {
    final current = await readSnapshotForSession(session: session);
    switch (response.status) {
      case EmergencyDirectoryStatus.unconfigured:
        return EmergencyDirectoryCacheResult(
          snapshot: current,
          usedCachedData: current != null,
        );
      case EmergencyDirectoryStatus.active:
        final disabledRevision = await _readDisabledRevision(
          _communityScopeHash(session),
        );
        if (disabledRevision != null && response.version! <= disabledRevision) {
          return EmergencyDirectoryCacheResult(
            snapshot: current,
            usedCachedData: current != null,
            hasConflict: true,
          );
        }
        final scoped = await readSnapshot(session: session);
        final latest = await readLatestSnapshotForSession(session: session);
        if (response.version! <= (scoped?.directory.version ?? 0) &&
            response.version! <= (latest?.directory.version ?? 0) &&
            scoped != null &&
            latest != null &&
            scoped.directory.version == latest.directory.version &&
            !scoped.directory.hasSameDirectoryData(latest.directory)) {
          return EmergencyDirectoryCacheResult(
            snapshot: scoped,
            usedCachedData: true,
            hasConflict: true,
          );
        }
        final next = EmergencyDirectoryCacheSnapshot(
          directory: response,
          syncedAt: syncedAt.toUtc(),
          communityName: session.communityName,
          rtLabel: session.rtLabel,
          communityScopeHash: _communityScopeHash(session),
        );
        if (current == null || response.version! > current.directory.version!) {
          await _writeSnapshot(session, next);
          return EmergencyDirectoryCacheResult(snapshot: next, didWrite: true);
        }
        if (response.version! < current.directory.version!) {
          return EmergencyDirectoryCacheResult(
            snapshot: current,
            usedCachedData: true,
          );
        }
        if (!response.hasSameDirectoryData(current.directory)) {
          return EmergencyDirectoryCacheResult(
            snapshot: current,
            usedCachedData: true,
            hasConflict: true,
          );
        }
        // A successful equal-revision response confirms the current directory.
        // Refresh local sync/verification metadata but not the data revision.
        await _writeSnapshot(session, next);
        return EmergencyDirectoryCacheResult(snapshot: next, didWrite: true);
      case EmergencyDirectoryStatus.disabled:
        final revision = response.version!;
        final cachedRevision = current?.directory.version;
        if (cachedRevision != null && revision < cachedRevision) {
          return EmergencyDirectoryCacheResult(
            snapshot: current,
            usedCachedData: true,
          );
        }
        if (cachedRevision != null && revision == cachedRevision) {
          // A status change without a new revision is an inconsistent backend
          // response. Do not erase a valid copy on a revision conflict.
          return EmergencyDirectoryCacheResult(
            snapshot: current,
            usedCachedData: true,
            hasConflict: true,
          );
        }
        final scopeHash = _communityScopeHash(session);
        final latestBeforeClear = await readLatestSnapshot();
        await _writeDisabledRevision(scopeHash, revision);
        await _localStore.delete(_cacheKey(session));
        if (latestBeforeClear?.communityScopeHash == scopeHash &&
            revision > latestBeforeClear!.directory.version!) {
          await _localStore.delete(_latestCacheKey);
        }
        return const EmergencyDirectoryCacheResult(didClear: true);
    }
  });

  Future<void> _writeSnapshot(
    ResidentSession session,
    EmergencyDirectoryCacheSnapshot snapshot,
  ) async {
    final directory = snapshot.directory;
    if (directory.status != EmergencyDirectoryStatus.active ||
        directory.version == null ||
        directory.lastVerifiedAt == null) {
      throw const FormatException(
        'Only valid ACTIVE directories can be cached.',
      );
    }
    final scopeHash = _communityScopeHash(session);
    final disabledRevision = await _readDisabledRevision(scopeHash);
    if (disabledRevision != null) {
      if (directory.version! <= disabledRevision) {
        throw const FormatException(
          'An older ACTIVE revision cannot replace a disabled directory.',
        );
      }
      await _localStore.delete(_disabledKey(scopeHash));
    }
    final value = <String, Object?>{
      'schemaVersion': 1,
      'syncedAt': snapshot.syncedAt.toUtc().toIso8601String(),
      'communityName': snapshot.communityName,
      'rtLabel': snapshot.rtLabel,
      'communityScopeHash': snapshot.communityScopeHash,
      'directory': directory.toWire(),
    };
    final encoded = jsonEncode(value);
    await _localStore.write(_cacheKey(session), encoded);
    await _localStore.write(_latestCacheKey, encoded);
  }

  String _communityScopeHash(ResidentSession session) =>
      sha256.convert(utf8.encode(session.communityId)).toString();

  String _disabledKey(String communityScopeHash) =>
      '$_disabledPrefix$communityScopeHash';

  Future<int?> _readDisabledRevision(String communityScopeHash) async {
    final encoded = await _localStore.read(_disabledKey(communityScopeHash));
    final revision = encoded == null ? null : int.tryParse(encoded);
    if (revision == null || revision <= 0 || revision > 9007199254740991) {
      return null;
    }
    return revision;
  }

  Future<void> _writeDisabledRevision(
    String communityScopeHash,
    int revision,
  ) async {
    final current = await _readDisabledRevision(communityScopeHash);
    if (current == null || revision > current) {
      await _localStore.write(_disabledKey(communityScopeHash), '$revision');
    }
  }

  String _cacheKey(ResidentSession session) {
    final scope = jsonEncode(<String>[session.communityId, session.residentId]);
    final digest = sha256.convert(utf8.encode(scope));
    return '$_cachePrefix$digest';
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _writeTail = _writeTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

Map<String, Object?> _readMap(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $name.');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _expectKeys(Map<String, Object?> value, Set<String> expected) {
  if (!value.keys.toSet().containsAll(expected) ||
      value.keys.any((key) => !expected.contains(key))) {
    throw const FormatException('Invalid emergency directory cache fields.');
  }
}

String _requiredText(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value.trim();
}

DateTime _date(Object? value, String name) {
  if (value is! String) throw FormatException('Invalid $name.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('Invalid $name.');
  return parsed.toUtc();
}
