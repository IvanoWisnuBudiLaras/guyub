import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/database/local_store.dart';
import '../application/task_push_notifications.dart';

String _identityScope(String identityId) {
  final normalized = identityId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(identityId, 'identityId', 'Must not be empty.');
  }
  return sha256.convert(utf8.encode(normalized)).toString();
}

final class FirebaseTaskPushNotificationsBoundary
    implements TaskPushNotificationsBoundary {
  const FirebaseTaskPushNotificationsBoundary({
    required this.messaging,
    required this.functions,
  });

  final FirebaseMessaging messaging;
  final FirebaseFunctions functions;

  @override
  Future<bool> hasNotificationPermission() async {
    final settings = await messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<bool> requestNotificationPermission() async {
    final settings = await messaging.requestPermission(
      alert: true,
      badge: false,
      sound: false,
      provisional: false,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  @override
  Future<String?> currentToken() => messaging.getToken();

  @override
  Stream<String> get tokenRefreshes => messaging.onTokenRefresh;

  @override
  Stream<TaskPushNotification> get openedNotifications => FirebaseMessaging
      .onMessageOpenedApp
      .map((message) => TaskPushNotification.fromData(message.data))
      .where((message) => message != null)
      .cast<TaskPushNotification>();

  @override
  Stream<TaskPushNotification> get foregroundNotifications => FirebaseMessaging
      .onMessage
      .map((message) => TaskPushNotification.fromData(message.data))
      .where((message) => message != null)
      .cast<TaskPushNotification>();

  @override
  Future<TaskPushNotification?> getInitialNotification() async {
    final message = await messaging.getInitialMessage();
    return message == null ? null : TaskPushNotification.fromData(message.data);
  }

  @override
  Future<void> registerResidentToken({
    required String sessionToken,
    required String token,
  }) async {
    await functions.httpsCallable('registerResidentPushToken').call({
      'sessionToken': sessionToken,
      'token': token,
      'platform': 'ANDROID',
    });
  }

  @override
  Future<void> unregisterResidentToken({
    required String sessionToken,
    required String token,
  }) async {
    await functions.httpsCallable('unregisterResidentPushToken').call({
      'sessionToken': sessionToken,
      'token': token,
    });
  }

  @override
  Future<void> registerPendampingToken({required String token}) async {
    await functions.httpsCallable('registerPendampingPushToken').call({
      'token': token,
      'platform': 'ANDROID',
    });
  }

  @override
  Future<void> unregisterPendampingToken({required String token}) async {
    await functions.httpsCallable('unregisterPendampingPushToken').call({
      'token': token,
    });
  }
}

final class LocalTaskPushPreferenceStore implements TaskPushPreferenceStore {
  const LocalTaskPushPreferenceStore(this.store);

  final LocalStore store;

  @override
  Future<bool> isEnabled(
    TaskPushAudience audience, {
    required String identityId,
  }) async => await store.read(_preferenceKey(audience, identityId)) == 'true';

  @override
  Future<void> setEnabled(
    TaskPushAudience audience, {
    required String identityId,
    required bool enabled,
  }) => store.write(
    _preferenceKey(audience, identityId),
    enabled ? 'true' : 'false',
  );

  String _preferenceKey(TaskPushAudience audience, String identityId) {
    // Legacy audience-only consent has no attributable identity and is ignored.
    final scopedIdentity = _identityScope(identityId);
    return switch (audience) {
      TaskPushAudience.resident => 'task_push_opt_in_resident_$scopedIdentity',
      TaskPushAudience.pendamping =>
        'task_push_opt_in_pendamping_$scopedIdentity',
    };
  }
}

final class FlutterSecureTaskPushDeviceTokenStore
    implements TaskPushDeviceTokenStore {
  FlutterSecureTaskPushDeviceTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _key(TaskPushAudience audience, String identityId) {
    final scopedIdentity = _identityScope(identityId);
    return switch (audience) {
      TaskPushAudience.resident =>
        'guyub_task_push_token_resident_$scopedIdentity',
      TaskPushAudience.pendamping =>
        'guyub_task_push_token_pendamping_$scopedIdentity',
    };
  }

  @override
  Future<String?> read(
    TaskPushAudience audience, {
    required String identityId,
  }) => _storage.read(key: _key(audience, identityId));

  @override
  Future<void> write(
    TaskPushAudience audience, {
    required String identityId,
    required String token,
  }) => _storage.write(key: _key(audience, identityId), value: token);

  @override
  Future<void> clear(TaskPushAudience audience, {required String identityId}) =>
      _storage.delete(key: _key(audience, identityId));
}
