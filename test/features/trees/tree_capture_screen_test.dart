import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/theme/app_theme.dart';
import 'package:guyub/features/auth/application/resident_session.dart';
import 'package:guyub/features/trees/application/device_location_service.dart';
import 'package:guyub/features/trees/application/tree_point_boundary.dart';
import 'package:guyub/features/trees/domain/tree_point.dart';
import 'package:guyub/features/trees/presentation/controllers/tree_point_controller.dart';
import 'package:guyub/features/trees/presentation/screens/tree_capture_screen.dart';
import 'package:image/image.dart' as img;

final class _FakeTreeBoundary implements TreePointBoundary {
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
    return TreePointSubmissionResult(
      treePointId: 'tp-101',
      status: TreePointStatus.pendingVerification,
      coarseLocation: const CoarseLocation(
        cellId: 'qw4z91p',
        approximateLat: -8.065,
        approximateLng: 111.901,
      ),
      submittedAt: DateTime.utc(2026, 10, 18),
    );
  }

  @override
  Future<CommunityTreeMap> listCommunityTreeMap({String? sessionToken}) async =>
      const CommunityTreeMap(items: [], totalVerifiedTrees: 0);

  @override
  Future<TreePointVerificationResult> verifyTreePoint({
    required String treePointId,
    required TreePointDecision decision,
    String? rejectionReason,
    required String commandId,
  }) async => TreePointVerificationResult(
    treePointId: treePointId,
    status: TreePointStatus.verified,
    verifiedAt: DateTime.utc(2026, 10, 18),
  );

  @override
  Future<void> deleteTreePoint({
    required String treePointId,
    String? reason,
  }) async {}
}

void main() {
  final session = ResidentSession(
    residentId: 'res-1',
    communityId: 'rt-01',
    communityName: 'RW 05 Melati',
    rtLabel: 'RT 03',
    nickname: 'Budi',
    expiresAt: DateTime.now().add(const Duration(days: 1)),
  );

  Uint8List createValidJpeg() {
    final image = img.Image(width: 50, height: 50);
    return Uint8List.fromList(img.encodeJpg(image));
  }

  Widget createTestWidget({
    required TreePointController controller,
    PickCameraImage? pickCameraImage,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: TreeCaptureScreen(
        session: session,
        taskId: 'task-greening-1',
        taskTitle: 'Tanam Pohon Resapan Pekarangan',
        controller: controller,
        pickCameraImage: pickCameraImage,
      ),
    );
  }

  testWidgets('shows privacy rationale sheet and accepts consent', (
    tester,
  ) async {
    final locationService = MockDeviceLocationService();
    final controller = TreePointController(
      boundary: _FakeTreeBoundary(),
      locationService: locationService,
      readSessionToken: () async => 'token-123',
    );

    await tester.pumpWidget(createTestWidget(controller: controller));
    await tester.pumpAndSettle();

    // Rationale bottom sheet must appear
    expect(find.text('Privasi Titik Pohon Guyub'), findsOneWidget);
    expect(
      find.textContaining('Grid Kasar (~150m)'),
      findsOneWidget,
    );

    // Agree to consent
    final agreeButton = find.byKey(const Key('tree-privacy-agree-button'));
    expect(agreeButton, findsOneWidget);
    await tester.tap(agreeButton);
    await tester.pumpAndSettle();

    // Main capture view is visible
    expect(find.text('Tanam & Dokumentasikan Pohon'), findsOneWidget);
    expect(find.text('Tugas: Tanam Pohon Resapan Pekarangan'), findsOneWidget);
    expect(find.textContaining('GPS Siap & Akurat'), findsOneWidget);
    expect(find.byKey(const Key('tree-capture-camera-button')), findsOneWidget);
    expect(find.text('Instruksi Keselamatan Terkunci:'), findsOneWidget);
  });

  testWidgets('full photo capture, species input, and submission flow', (
    tester,
  ) async {
    final locationService = MockDeviceLocationService();
    final controller = TreePointController(
      boundary: _FakeTreeBoundary(),
      locationService: locationService,
      readSessionToken: () async => 'token-123',
    );

    final validJpeg = createValidJpeg();

    await tester.pumpWidget(
      createTestWidget(
        controller: controller,
        pickCameraImage: () async => validJpeg,
      ),
    );
    await tester.pumpAndSettle();

    // Accept privacy
    await tester.tap(find.byKey(const Key('tree-privacy-agree-button')));
    await tester.pumpAndSettle();

    // Shutter button
    final cameraButton = find.byKey(const Key('tree-capture-camera-button'));
    await tester.tap(cameraButton);
    await tester.pumpAndSettle();

    // Image preview must be shown
    expect(find.byKey(const Key('tree-captured-preview')), findsOneWidget);
    expect(find.byKey(const Key('tree-retake-photo-button')), findsOneWidget);

    // Enter species hint
    await tester.enterText(
      find.byKey(const Key('tree-species-input')),
      'Mangga Manalagi',
    );
    await tester.pumpAndSettle();

    // Submit button is now enabled
    final submitButton = find.byKey(const Key('tree-submit-button'));
    expect(submitButton, findsOneWidget);
    await tester.ensureVisible(submitButton);
    await tester.pumpAndSettle();
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    // Success screen
    expect(find.text('Titik Pohon Berhasil Diajukan!'), findsOneWidget);
    expect(find.text('Menunggu Verifikasi RT'), findsOneWidget);
    expect(find.text('qw4z91p'), findsOneWidget);
    expect(find.byKey(const Key('tree-success-back-button')), findsOneWidget);
  });
}
