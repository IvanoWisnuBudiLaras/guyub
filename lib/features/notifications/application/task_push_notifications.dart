import 'dart:async';

import '../../auth/application/operator_profile.dart';
import '../../auth/application/resident_session.dart';

const _taskIdPattern = r'^[a-f0-9]{40}$';

/// Safe, allowlisted routing data. Notification previews never contain task or resident details.
final class TaskPushNotification {
  const TaskPushNotification({required this.eventType, required this.taskId});

  final String eventType;
  final String taskId;

  static final RegExp _taskId = RegExp(_taskIdPattern);
  static const Set<String> _eventTypes = {
    'TASK_ACTIVATED',
    'TASK_REMINDER',
    'TASK_ESCALATION',
    'TASK_VERIFICATION_NEEDED',
    'TASK_CANCELLED',
    'TASK_CLOSED',
  };

  static TaskPushNotification? fromData(Map<String, dynamic> data) {
    final eventType = data['eventType'];
    final taskId = data['taskId'];
    if (eventType is! String ||
        !_eventTypes.contains(eventType) ||
        taskId is! String ||
        !_taskId.hasMatch(taskId)) {
      return null;
    }
    return TaskPushNotification(eventType: eventType, taskId: taskId);
  }
}

enum TaskPushAudience { resident, pendamping }

enum TaskPushOptInResult { enabled, permissionDenied, unavailable }

abstract interface class TaskPushNotificationsBoundary {
  Future<bool> hasNotificationPermission();
  Future<bool> requestNotificationPermission();
  Future<String?> currentToken();
  Stream<String> get tokenRefreshes;
  Stream<TaskPushNotification> get openedNotifications;
  Stream<TaskPushNotification> get foregroundNotifications;
  Future<TaskPushNotification?> getInitialNotification();
  Future<void> registerResidentToken({
    required String sessionToken,
    required String token,
  });
  Future<void> unregisterResidentToken({
    required String sessionToken,
    required String token,
  });
  Future<void> registerPendampingToken({required String token});
  Future<void> unregisterPendampingToken({required String token});
}

abstract interface class TaskPushPreferenceStore {
  Future<bool> isEnabled(
    TaskPushAudience audience, {
    required String identityId,
  });
  Future<void> setEnabled(
    TaskPushAudience audience, {
    required String identityId,
    required bool enabled,
  });
}

/// Stores the last FCM token in secure storage so token refresh can unregister the old token.
abstract interface class TaskPushDeviceTokenStore {
  Future<String?> read(TaskPushAudience audience, {required String identityId});
  Future<void> write(
    TaskPushAudience audience, {
    required String identityId,
    required String token,
  });
  Future<void> clear(TaskPushAudience audience, {required String identityId});
}

sealed class _PushTarget {
  const _PushTarget();
  TaskPushAudience get audience;
  String get identityId;
}

final class _ResidentPushTarget extends _PushTarget {
  const _ResidentPushTarget(this.session);
  final ResidentSession session;
  @override
  TaskPushAudience get audience => TaskPushAudience.resident;
  @override
  String get identityId => session.residentId;
}

final class _PendampingPushTarget extends _PushTarget {
  const _PendampingPushTarget(this.profile);
  final OperatorProfile profile;
  @override
  TaskPushAudience get audience => TaskPushAudience.pendamping;
  @override
  String get identityId => profile.uid;
}

/// Handles explicit opt-in, scoped token registration, token refresh and click routing.
/// Registration errors never affect access to tasks stored by the task boundary.
final class TaskPushNotificationsController {
  TaskPushNotificationsController({
    required TaskPushNotificationsBoundary boundary,
    required TaskPushPreferenceStore preferences,
    required TaskPushDeviceTokenStore deviceTokens,
    required Future<String?> Function() readResidentSessionToken,
  }) : this._internal(
         boundary,
         preferences,
         deviceTokens,
         readResidentSessionToken,
       );

  TaskPushNotificationsController._internal(
    this._boundary,
    this._preferences,
    this._deviceTokens,
    this._readResidentSessionToken,
  ) {
    _openedSubscription = _boundary.openedNotifications.listen((message) {
      _opened.add(message);
    });
    _foregroundSubscription = _boundary.foregroundNotifications.listen((
      message,
    ) {
      _foreground.add(message);
    });
    _refreshSubscription = _boundary.tokenRefreshes.listen((token) {
      unawaited(_registerForCurrentTarget(token));
    });
    _initialNotification = _boundary.getInitialNotification();
  }

  final TaskPushNotificationsBoundary _boundary;
  final TaskPushPreferenceStore _preferences;
  final TaskPushDeviceTokenStore _deviceTokens;
  final Future<String?> Function() _readResidentSessionToken;
  final StreamController<TaskPushNotification> _opened =
      StreamController<TaskPushNotification>.broadcast();
  final StreamController<TaskPushNotification> _foreground =
      StreamController<TaskPushNotification>.broadcast();
  late final StreamSubscription<TaskPushNotification> _openedSubscription;
  late final StreamSubscription<TaskPushNotification> _foregroundSubscription;
  late final StreamSubscription<String> _refreshSubscription;
  late final Future<TaskPushNotification?> _initialNotification;
  _PushTarget? _activeTarget;
  TaskPushNotification? _cachedInitialNotification;
  bool _initialNotificationRead = false;
  bool _initialConsumed = false;

  Stream<TaskPushNotification> get openedNotifications => _opened.stream;
  Stream<TaskPushNotification> get foregroundNotifications =>
      _foreground.stream;

  Future<TaskPushNotification?> readPendingInitialNotification() async {
    if (_initialConsumed) return null;
    if (_initialNotificationRead) return _cachedInitialNotification;
    try {
      _cachedInitialNotification = await _initialNotification;
    } catch (_) {
      _cachedInitialNotification = null;
    }
    _initialNotificationRead = true;
    return _cachedInitialNotification;
  }

  void acknowledgeInitialNotification(TaskPushNotification notification) {
    final initial = _cachedInitialNotification;
    if (_initialConsumed || !_initialNotificationRead || initial == null) {
      return;
    }
    if (initial.eventType == notification.eventType &&
        initial.taskId == notification.taskId) {
      _initialConsumed = true;
    }
  }

  Future<bool> isEnabled(
    TaskPushAudience audience, {
    required String identityId,
  }) => _preferences.isEnabled(audience, identityId: identityId);

  Future<void> syncResidentSession(ResidentSession session) async {
    if (session.isOfflineSnapshot) return;
    _activeTarget = _ResidentPushTarget(session);
    await _syncIfOptedIn();
  }

  Future<void> syncPendamping(OperatorProfile profile) async {
    if (profile.role != OperatorRole.pendampingRt) return;
    _activeTarget = _PendampingPushTarget(profile);
    await _syncIfOptedIn();
  }

  Future<TaskPushOptInResult> enableResident(ResidentSession session) async {
    if (session.isOfflineSnapshot) return TaskPushOptInResult.unavailable;
    final target = _ResidentPushTarget(session);
    _activeTarget = target;
    final granted = await _boundary.requestNotificationPermission();
    if (!granted) {
      await _preferences.setEnabled(
        TaskPushAudience.resident,
        identityId: session.residentId,
        enabled: false,
      );
      return TaskPushOptInResult.permissionDenied;
    }
    await _preferences.setEnabled(
      TaskPushAudience.resident,
      identityId: session.residentId,
      enabled: true,
    );
    try {
      final token = await _boundary.currentToken();
      if (token == null || token.isEmpty) {
        return TaskPushOptInResult.unavailable;
      }
      await _registerForTarget(target, token);
      return TaskPushOptInResult.enabled;
    } catch (_) {
      return TaskPushOptInResult.unavailable;
    }
  }

  Future<TaskPushOptInResult> enablePendamping(OperatorProfile profile) async {
    if (profile.role != OperatorRole.pendampingRt) {
      return TaskPushOptInResult.unavailable;
    }
    final target = _PendampingPushTarget(profile);
    _activeTarget = target;
    final granted = await _boundary.requestNotificationPermission();
    if (!granted) {
      await _preferences.setEnabled(
        TaskPushAudience.pendamping,
        identityId: profile.uid,
        enabled: false,
      );
      return TaskPushOptInResult.permissionDenied;
    }
    await _preferences.setEnabled(
      TaskPushAudience.pendamping,
      identityId: profile.uid,
      enabled: true,
    );
    try {
      final token = await _boundary.currentToken();
      if (token == null || token.isEmpty) {
        return TaskPushOptInResult.unavailable;
      }
      await _registerForTarget(target, token);
      return TaskPushOptInResult.enabled;
    } catch (_) {
      return TaskPushOptInResult.unavailable;
    }
  }

  Future<void> disableResident(ResidentSession session) async {
    await _preferences.setEnabled(
      TaskPushAudience.resident,
      identityId: session.residentId,
      enabled: false,
    );
    try {
      final token = await _deviceTokens.read(
        TaskPushAudience.resident,
        identityId: session.residentId,
      );
      if (token != null && token.isNotEmpty) {
        final sessionToken = await _readResidentSessionToken();
        if (sessionToken == null || sessionToken.isEmpty) {
          throw StateError(
            'Resident session is unavailable for token revocation.',
          );
        }
        await _boundary.unregisterResidentToken(
          sessionToken: sessionToken,
          token: token,
        );
        await _deviceTokens.clear(
          TaskPushAudience.resident,
          identityId: session.residentId,
        );
      }
    } catch (_) {
      await _preferences.setEnabled(
        TaskPushAudience.resident,
        identityId: session.residentId,
        enabled: true,
      );
      rethrow;
    }
    final activeTarget = _activeTarget;
    if (activeTarget is _ResidentPushTarget &&
        activeTarget.session.residentId == session.residentId) {
      _activeTarget = null;
    }
  }

  Future<void> disablePendamping(OperatorProfile profile) async {
    await _preferences.setEnabled(
      TaskPushAudience.pendamping,
      identityId: profile.uid,
      enabled: false,
    );
    try {
      final token = await _deviceTokens.read(
        TaskPushAudience.pendamping,
        identityId: profile.uid,
      );
      if (token != null && token.isNotEmpty) {
        await _boundary.unregisterPendampingToken(token: token);
        await _deviceTokens.clear(
          TaskPushAudience.pendamping,
          identityId: profile.uid,
        );
      }
    } catch (_) {
      await _preferences.setEnabled(
        TaskPushAudience.pendamping,
        identityId: profile.uid,
        enabled: true,
      );
      rethrow;
    } finally {
      final activeTarget = _activeTarget;
      if (activeTarget is _PendampingPushTarget &&
          activeTarget.profile.uid == profile.uid &&
          await _preferences.isEnabled(
                TaskPushAudience.pendamping,
                identityId: profile.uid,
              ) ==
              false) {
        _activeTarget = null;
      }
    }
  }

  /// Clears only device-local resident push state after server-side deletion.
  Future<void> clearResidentStateAfterDeletion(ResidentSession session) async {
    final activeTarget = _activeTarget;
    if (activeTarget is _ResidentPushTarget &&
        activeTarget.session.residentId == session.residentId) {
      _activeTarget = null;
    }
    await _preferences.setEnabled(
      TaskPushAudience.resident,
      identityId: session.residentId,
      enabled: false,
    );
    await _deviceTokens.clear(
      TaskPushAudience.resident,
      identityId: session.residentId,
    );
  }

  /// Called before local sign-out so a token refresh cannot re-register a signed-out account.
  void clearActiveTarget() => _activeTarget = null;

  Future<void> unregisterResidentBeforeSignOut(ResidentSession session) async {
    final activeTarget = _activeTarget;
    if (activeTarget is _ResidentPushTarget &&
        activeTarget.session.residentId == session.residentId) {
      _activeTarget = null;
    }
    try {
      final token = await _deviceTokens.read(
        TaskPushAudience.resident,
        identityId: session.residentId,
      );
      if (token == null || token.isEmpty) return;
      final sessionToken = await _readResidentSessionToken();
      if (sessionToken == null || sessionToken.isEmpty) return;
      await _boundary.unregisterResidentToken(
        sessionToken: sessionToken,
        token: token,
      );
      await _deviceTokens.clear(
        TaskPushAudience.resident,
        identityId: session.residentId,
      );
    } catch (_) {
      // Sign-out remains available if best-effort token cleanup is unavailable.
    }
  }

  Future<void> unregisterPendampingBeforeSignOut(
    OperatorProfile profile,
  ) async {
    if (profile.role != OperatorRole.pendampingRt) return;
    final activeTarget = _activeTarget;
    if (activeTarget is _PendampingPushTarget &&
        activeTarget.profile.uid == profile.uid) {
      _activeTarget = null;
    }
    try {
      final token = await _deviceTokens.read(
        TaskPushAudience.pendamping,
        identityId: profile.uid,
      );
      if (token == null || token.isEmpty) return;
      await _boundary.unregisterPendampingToken(token: token);
      await _deviceTokens.clear(
        TaskPushAudience.pendamping,
        identityId: profile.uid,
      );
    } catch (_) {
      // Live operator membership is still rechecked before any delivery.
    }
  }

  Future<void> dispose() async {
    await _openedSubscription.cancel();
    await _foregroundSubscription.cancel();
    await _refreshSubscription.cancel();
    _activeTarget = null;
  }

  Future<void> _syncIfOptedIn() async {
    final target = _activeTarget;
    if (target == null ||
        !await _preferences.isEnabled(
          target.audience,
          identityId: target.identityId,
        )) {
      return;
    }
    try {
      if (!await _boundary.hasNotificationPermission()) {
        await _unregisterStoredToken(target);
        return;
      }
      final token = await _boundary.currentToken();
      if (token != null && token.isNotEmpty) {
        await _registerForTarget(target, token);
      }
    } catch (_) {
      // Push is a delivery hint; task access remains pull-based and available.
    }
  }

  Future<void> _registerForCurrentTarget(String token) async {
    final target = _activeTarget;
    if (target == null || token.isEmpty) return;
    try {
      if (await _preferences.isEnabled(
            target.audience,
            identityId: target.identityId,
          ) &&
          await _boundary.hasNotificationPermission()) {
        await _registerForTarget(target, token);
      }
    } catch (_) {
      // A failed token refresh never invalidates task availability.
    }
  }

  Future<void> _registerForTarget(_PushTarget target, String token) async {
    final oldToken = await _deviceTokens.read(
      target.audience,
      identityId: target.identityId,
    );
    if (oldToken != null && oldToken.isNotEmpty && oldToken != token) {
      try {
        await _unregisterToken(target, oldToken);
      } catch (_) {
        // Register the new token even if cleanup of an obsolete token is unavailable.
      }
    }
    if (target is _ResidentPushTarget) {
      final sessionToken = await _readResidentSessionToken();
      if (sessionToken == null || sessionToken.isEmpty) return;
      await _boundary.registerResidentToken(
        sessionToken: sessionToken,
        token: token,
      );
    } else if (target is _PendampingPushTarget) {
      await _boundary.registerPendampingToken(token: token);
    }
    await _deviceTokens.write(
      target.audience,
      identityId: target.identityId,
      token: token,
    );
  }

  Future<void> _unregisterStoredToken(_PushTarget target) async {
    final token = await _deviceTokens.read(
      target.audience,
      identityId: target.identityId,
    );
    if (token == null || token.isEmpty) return;
    await _unregisterToken(target, token);
    await _deviceTokens.clear(target.audience, identityId: target.identityId);
  }

  Future<void> _unregisterToken(_PushTarget target, String token) async {
    if (target is _ResidentPushTarget) {
      final sessionToken = await _readResidentSessionToken();
      if (sessionToken == null || sessionToken.isEmpty) return;
      await _boundary.unregisterResidentToken(
        sessionToken: sessionToken,
        token: token,
      );
    } else if (target is _PendampingPushTarget) {
      await _boundary.unregisterPendampingToken(token: token);
    }
  }
}
