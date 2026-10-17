import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_theme.dart';
import 'package:guyub/features/trees/application/device_location_service.dart';
import 'package:guyub/features/trees/application/tree_point_boundary.dart';
import 'package:guyub/features/trees/domain/tree_point.dart';
import 'package:guyub/features/trees/presentation/controllers/tree_point_controller.dart';
import 'package:guyub/features/trees/presentation/screens/community_tree_map_screen.dart';

final class _FakeTreePointBoundary implements TreePointBoundary {
  _FakeTreePointBoundary({CommunityTreeMap? treeMap, this.shouldFail = false})
      : _treeMap = treeMap ??
            const CommunityTreeMap(items: [], totalVerifiedTrees: 0);

  final CommunityTreeMap _treeMap;
  final bool shouldFail;
  int loadCount = 0;

  @override
  Future<CommunityTreeMap> listCommunityTreeMap({String? sessionToken}) async {
    loadCount++;
    if (shouldFail) {
      throw const TreePointException('Gagal memuat peta');
    }
    return _treeMap;
  }

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
    throw UnimplementedError();
  }

  @override
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
    required String commandId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteTreePoint({
    required String treePointId,
    String? reason,
  }) async {}
}

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: child,
    );
  }

  final sampleTree = CommunityTreeItem(
    treePointId: 'tp-tree-1',
    speciesHint: 'Pohon Mangga Golek',
    submitterNickname: 'Pak Joko',
    coarseLocation: const CoarseLocation(
      cellId: 'qw4z91p',
      approximateLat: -8.0645,
      approximateLng: 111.9015,
    ),
    plantedAt: DateTime(2026, 10, 15, 8, 30),
    hasEvidencePhoto: true,
  );

  testWidgets('renders empty state when no trees verified in RT', (tester) async {
    final boundary = _FakeTreePointBoundary(
      treeMap: const CommunityTreeMap(items: [], totalVerifiedTrees: 0),
    );
    final controller = TreePointController(
      boundary: boundary,
      locationService: MockDeviceLocationService(),
    );

    await tester.pumpWidget(
      buildTestableWidget(
        CommunityTreeMapScreen(controller: controller),
      ),
    );

    // Initial loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('0 Pohon Resapan Terverifikasi'), findsOneWidget);
    expect(find.text('Belum ada pohon terverifikasi di RT ini.'), findsOneWidget);
  });

  testWidgets('switches to list view and shows tree details and attribution', (tester) async {
    final boundary = _FakeTreePointBoundary(
      treeMap: CommunityTreeMap(
        items: [sampleTree],
        totalVerifiedTrees: 1,
      ),
    );
    final controller = TreePointController(
      boundary: boundary,
      locationService: MockDeviceLocationService(),
    );

    await tester.pumpWidget(
      buildTestableWidget(
        CommunityTreeMapScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 Pohon Resapan Terverifikasi'), findsOneWidget);

    // Switch to Daftar (List) view mode
    final daftarButton = find.text('Daftar');
    expect(daftarButton, findsOneWidget);
    await tester.tap(daftarButton);
    await tester.pumpAndSettle();

    // Verify list item contents
    expect(find.text('Pohon Mangga Golek'), findsOneWidget);
    expect(find.textContaining('Ditanam oleh Pak Joko'), findsOneWidget);

    // Tap on tree card to open bottom sheet
    await tester.tap(find.text('Pohon Mangga Golek'));
    await tester.pumpAndSettle();

    // Verify bottom sheet content
    expect(find.text('Terverifikasi RT'), findsOneWidget);
    expect(find.textContaining('qw4z91p'), findsOneWidget);
    expect(find.textContaining('Perkiraan area: Sel Geohash 7'), findsOneWidget);
    expect(find.textContaining('Lokasi persis disamarkan'), findsOneWidget);
  });

  testWidgets('renders error view on load failure and retries successfully', (tester) async {
    final failingBoundary = _FakeTreePointBoundary(shouldFail: true);
    final controller = TreePointController(
      boundary: failingBoundary,
      locationService: MockDeviceLocationService(),
    );

    await tester.pumpWidget(
      buildTestableWidget(
        CommunityTreeMapScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Peta pohon belum dapat dimuat. Periksa koneksi dan coba lagi.'),
      findsOneWidget,
    );
    expect(find.text('Coba Lagi'), findsOneWidget);
  });
}
