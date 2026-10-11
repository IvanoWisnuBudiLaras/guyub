import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/database/local_store.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/auth/application/resident_session_vault.dart';
import 'package:guyub/features/emergency/application/emergency_directory.dart';
import 'package:guyub/features/emergency/application/emergency_directory_boundary.dart';
import 'package:guyub/features/emergency/application/emergency_directory_controller.dart';
import 'package:guyub/features/emergency/data/emergency_directory_cache.dart';
import 'package:guyub/features/emergency/presentation/emergency_directory_screen.dart';

void main() {
  final verifiedAt = DateTime.now().toUtc().subtract(
    const Duration(minutes: 2),
  );
  final syncedAt = DateTime.now().toUtc();

  Map<String, Object?> activeWire({
    int version = 1,
    String phone = '112',
    String location = 'Balai warga',
    String? lastVerifiedAt,
    List<Object?>? contacts,
    List<Object?>? assemblyPoints,
    List<Object?>? officialChannels,
  }) => {
    'state': 'ACTIVE',
    'version': version,
    'lastVerifiedAt': lastVerifiedAt ?? verifiedAt.toIso8601String(),
    'emergencyContacts':
        contacts ??
        [
          {'label': 'Petugas RT', 'phone': phone},
        ],
    'assemblyPoints':
        assemblyPoints ??
        [
          {'label': 'Titik kumpul', 'publicLocation': location},
        ],
    'officialReportChannels':
        officialChannels ??
        [
          {'label': 'Lapor resmi', 'url': 'https://lapor.example.id'},
        ],
  };

  EmergencyDirectoryResponse active({
    int version = 1,
    String phone = '112',
    String location = 'Balai warga',
    DateTime? lastVerified,
  }) => EmergencyDirectoryResponse.fromWire(
    activeWire(
      version: version,
      phone: phone,
      location: location,
      lastVerifiedAt: lastVerified?.toIso8601String(),
    ),
  );

  EmergencyDirectoryResponse disabled(int version) =>
      EmergencyDirectoryResponse.fromWire({
        'state': 'DISABLED',
        'version': version,
        'lastVerifiedAt': verifiedAt.toIso8601String(),
      });

  ResidentSession session({
    String residentId = 'resident-secret-id',
    String communityId = 'community-id-rt-03',
    String communityName = 'Kelurahan Mawar',
    String rtLabel = 'RT 03 / RW 02',
  }) => ResidentSession(
    residentId: residentId,
    communityId: communityId,
    communityName: communityName,
    rtLabel: rtLabel,
    nickname: 'Warga',
    expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
  );

  group('EmergencyDirectoryResponse strict parser', () {
    test('parses ACTIVE, DISABLED, and UNCONFIGURED wire variants', () {
      final activeResponse = EmergencyDirectoryResponse.fromWire(activeWire());
      expect(activeResponse.status, EmergencyDirectoryStatus.active);
      expect(activeResponse.version, 1);
      expect(activeResponse.emergencyContacts.single.phone, '112');
      expect(
        EmergencyDirectoryResponse.fromWire({'state': 'UNCONFIGURED'}).status,
        EmergencyDirectoryStatus.unconfigured,
      );
      expect(
        EmergencyDirectoryResponse.fromWire({
          'state': 'DISABLED',
          'version': 2,
          'lastVerifiedAt': verifiedAt.toIso8601String(),
        }).status,
        EmergencyDirectoryStatus.disabled,
      );
    });

    test('rejects malformed values and server-invalid bounds', () {
      expect(
        () => EmergencyDirectoryResponse.fromWire({
          ...activeWire(),
          'version': 0,
        }),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire({
          ...activeWire(),
          'unexpected': true,
        }),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            lastVerifiedAt: DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            contacts: List<Object?>.filled(11, {'label': 'R', 'phone': '112'}),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(assemblyPoints: const []),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            contacts: [
              {'label': 'Petugas', 'phone': 'hubungi saya'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            contacts: [
              {'label': 'Petugas', 'phone': '+12'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            contacts: [
              {'label': 'Petugas', 'phone': '+1234567890123456'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            contacts: [
              {'label': List<String>.filled(81, 'L').join(), 'phone': '112'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            assemblyPoints: [
              {
                'label': 'Titik',
                'publicLocation': List<String>.filled(241, 'J').join(),
              },
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            officialChannels: [
              {'label': 'Kanal', 'url': 'http://lapor.example.id'},
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => EmergencyDirectoryResponse.fromWire(
          activeWire(
            officialChannels: List<Object?>.filled(11, {
              'label': 'Kanal',
              'phone': '112',
            }),
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('EmergencyDirectoryCache', () {
    test(
      'keeps current revision across unconfigured and older responses',
      () async {
        final store = InspectableLocalStore();
        final cache = EmergencyDirectoryCache(store);
        final user = session();
        final first = active(version: 4);
        await cache.applyResponse(
          session: user,
          response: first,
          syncedAt: syncedAt,
        );

        final unconfigured = await cache.applyResponse(
          session: user,
          response: EmergencyDirectoryResponse.fromWire({
            'state': 'UNCONFIGURED',
          }),
          syncedAt: syncedAt.add(const Duration(minutes: 1)),
        );
        expect(unconfigured.snapshot?.directory.version, 4);
        expect(unconfigured.usedCachedData, isTrue);

        final older = await cache.applyResponse(
          session: user,
          response: active(version: 3, phone: '113'),
          syncedAt: syncedAt.add(const Duration(minutes: 2)),
        );
        expect(older.snapshot?.directory.version, 4);
        expect(older.snapshot?.directory.emergencyContacts.single.phone, '112');
        expect(older.usedCachedData, isTrue);
      },
    );

    test('same revision data conflicts; newer disabled revision clears both caches', () async {
      final store = InspectableLocalStore();
      final cache = EmergencyDirectoryCache(store);
      final user = session();
      await cache.applyResponse(
        session: user,
        response: active(version: 4),
        syncedAt: syncedAt,
      );

      final conflict = await cache.applyResponse(
        session: user,
        response: active(version: 4, phone: '113'),
        syncedAt: syncedAt.add(const Duration(minutes: 1)),
      );
      expect(conflict.hasConflict, isTrue);
      expect(
        conflict.snapshot?.directory.emergencyContacts.single.phone,
        '112',
      );

      final disabledOld = await cache.applyResponse(
        session: user,
        response: disabled(3),
        syncedAt: syncedAt,
      );
      expect(disabledOld.snapshot?.directory.version, 4);
      expect(disabledOld.usedCachedData, isTrue);

      final disabledCurrent = await cache.applyResponse(
        session: user,
        response: disabled(4),
        syncedAt: syncedAt,
      );
      expect(disabledCurrent.hasConflict, isTrue);
      expect(await cache.readSnapshot(session: user), isNotNull);

      final disabledNewer = await cache.applyResponse(
        session: user,
        response: disabled(5),
        syncedAt: syncedAt,
      );
      expect(disabledNewer.didClear, isTrue);
      expect(await cache.readSnapshot(session: user), isNull);
      expect(await cache.readLatestSnapshot(), isNull);
    });

    test(
      'keeps cache isolated by RT and loads latest public copy without session',
      () async {
        final store = InspectableLocalStore();
        final cache = EmergencyDirectoryCache(store);
        final rt03 = session();
        final rt04 = session(
          communityId: 'community-id-rt-04',
          communityName: 'Kelurahan Melati',
          rtLabel: 'RT 04 / RW 02',
        );
        await cache.applyResponse(
          session: rt03,
          response: active(),
          syncedAt: syncedAt,
        );
        expect(await cache.readSnapshot(session: rt04), isNull);
        final latest = await cache.readLatestSnapshot();
        expect(latest?.rtLabel, 'RT 03 / RW 02');
        expect(latest?.communityName, 'Kelurahan Mawar');

        await cache.applyResponse(
          session: rt04,
          response: active(version: 2, phone: '113'),
          syncedAt: syncedAt.add(const Duration(minutes: 1)),
        );
        expect((await cache.readLatestSnapshot())?.rtLabel, 'RT 04 / RW 02');
      },
    );

    test(
      'disabled response for another RT cannot clear latest public copy',
      () async {
        final store = InspectableLocalStore();
        final cache = EmergencyDirectoryCache(store);
        final rt03 = session();
        final rt04 = session(
          communityId: 'community-id-rt-04',
          communityName: 'Kelurahan Melati',
          rtLabel: 'RT 04 / RW 02',
        );
        await cache.applyResponse(
          session: rt03,
          response: active(version: 1),
          syncedAt: syncedAt,
        );
        await cache.applyResponse(
          session: rt04,
          response: active(version: 2),
          syncedAt: syncedAt,
        );
        await cache.applyResponse(
          session: rt03,
          response: disabled(3),
          syncedAt: syncedAt,
        );
        expect((await cache.readLatestSnapshot())?.rtLabel, 'RT 04 / RW 02');
      },
    );

    test(
      'new disabled revision invalidates stale resident cache on same device',
      () async {
        final store = InspectableLocalStore();
        final cache = EmergencyDirectoryCache(store);
        final firstResident = session();
        final secondResident = session(residentId: 'resident-second');
        await cache.applyResponse(
          session: firstResident,
          response: active(version: 4),
          syncedAt: syncedAt,
        );

        final disabledResult = await cache.applyResponse(
          session: secondResident,
          response: disabled(5),
          syncedAt: syncedAt.add(const Duration(minutes: 1)),
        );
        expect(disabledResult.didClear, isTrue);
        expect(await cache.readSnapshot(session: firstResident), isNull);
        expect(await cache.readLatestSnapshot(), isNull);

        final olderActive = await cache.applyResponse(
          session: firstResident,
          response: active(version: 4, phone: '113'),
          syncedAt: syncedAt.add(const Duration(minutes: 2)),
        );
        expect(olderActive.hasConflict, isTrue);
        expect(await cache.readSnapshot(session: firstResident), isNull);

        await cache.applyResponse(
          session: firstResident,
          response: active(version: 6),
          syncedAt: syncedAt.add(const Duration(minutes: 3)),
        );
        expect(
          (await cache.readSnapshot(session: firstResident))?.directory.version,
          6,
        );
      },
    );

    test('cache values never contain token or resident identifiers', () async {
      final store = InspectableLocalStore();
      final cache = EmergencyDirectoryCache(store);
      final user = session();
      await cache.applyResponse(
        session: user,
        response: active(),
        syncedAt: syncedAt,
      );
      final values = store.values.values.join(' ');
      expect(values, isNot(contains('secret-session-token')));
      expect(values, isNot(contains(user.residentId)));
      expect(values, isNot(contains(user.communityId)));
      expect(values, contains(user.communityName));
      expect(values, contains(user.rtLabel));
      expect(
        (await cache.readSnapshot(session: user))?.communityScopeHash,
        isNotEmpty,
      );
    });
  });

  group('EmergencyDirectoryController and screen', () {
    test('older ACTIVE response does not cross a disabled revision', () async {
      final cache = EmergencyDirectoryCache(InspectableLocalStore());
      final user = session();
      await cache.applyResponse(
        session: user,
        response: disabled(5),
        syncedAt: syncedAt,
      );
      final controller = EmergencyDirectoryController(
        boundary: FakeEmergencyBoundary((_) async => active(version: 4)),
        cache: cache,
        vault: FakeResidentSessionVault('secret-session-token'),
      );

      await controller.load(session: user);

      expect(controller.state.hasConflict, isTrue);
      expect(controller.state.snapshot, isNull);
      controller.dispose();
    });

    test(
      'no-cache network failure becomes a readable unavailable state',
      () async {
        final cache = EmergencyDirectoryCache(InspectableLocalStore());
        final controller = EmergencyDirectoryController(
          boundary: FakeEmergencyBoundary(
            (_) async => throw StateError('offline'),
          ),
          cache: cache,
          vault: FakeResidentSessionVault('secret-session-token'),
        );
        await controller.load(session: session());
        expect(
          controller.state.status,
          EmergencyDirectoryViewStatus.unavailable,
        );
        expect(controller.state.snapshot, isNull);
        expect(controller.state.isRefreshing, isFalse);
        controller.dispose();
      },
    );

    testWidgets(
      'unauthenticated emergency screen shows latest cached RT offline',
      (tester) async {
        final store = InspectableLocalStore();
        final cache = EmergencyDirectoryCache(store);
        final user = session();
        await cache.applyResponse(
          session: user,
          response: active(),
          syncedAt: syncedAt,
        );
        final boundary = FakeEmergencyBoundary((_) async {
          fail('Unauthenticated screen must not call the backend.');
        });
        final controller = EmergencyDirectoryController(
          boundary: boundary,
          cache: cache,
          vault: FakeResidentSessionVault(null),
        );

        await tester.pumpWidget(
          MaterialApp(home: EmergencyDirectoryScreen(controller: controller)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Mode offline • menampilkan direktori yang tersimpan di perangkat.',
          ),
          findsOneWidget,
        );
        expect(find.text('Kelurahan Mawar • RT 03 / RW 02'), findsOneWidget);
        expect(
          find.text(
            'Pastikan wilayah ini sesuai dengan lokasi Anda. Direktori ini tidak berlaku otomatis untuk RT lain.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Terakhir disinkronkan:'), findsOneWidget);
        expect(find.textContaining('Terakhir diverifikasi:'), findsOneWidget);
        expect(find.text('112'), findsOneWidget);
        expect(find.text('Balai warga'), findsOneWidget);
        expect(boundary.callCount, 0);
        controller.dispose();
      },
    );
  });
}

final class FakeEmergencyBoundary implements EmergencyDirectoryBoundary {
  FakeEmergencyBoundary(this.handler);

  final Future<EmergencyDirectoryResponse> Function(String token) handler;
  int callCount = 0;

  @override
  Future<EmergencyDirectoryResponse> getEmergencyDirectory({
    required String sessionToken,
  }) {
    callCount++;
    return handler(sessionToken);
  }
}

final class FakeResidentSessionVault implements ResidentSessionVault {
  FakeResidentSessionVault(this.token);

  String? token;

  @override
  Future<void> clear() async => token = null;

  @override
  Future<void> clearPendingEnrollmentId() async {}

  @override
  Future<String?> read() async => token;

  @override
  Future<String?> readPendingEnrollmentId() async => null;

  @override
  Future<void> write(String sessionToken) async => token = sessionToken;

  @override
  Future<void> writePendingEnrollmentId(String requestId) async {}
}

final class InspectableLocalStore implements LocalStore {
  final Map<String, String> values = {};

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<void> close() async {}

  @override
  Future<bool> containsKey(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
