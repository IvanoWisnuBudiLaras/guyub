import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/evidence/application/task_evidence_boundary.dart';
import 'package:guyub/features/trees/application/device_location_service.dart';
import 'package:guyub/features/trees/application/tree_point_boundary.dart';
import 'package:guyub/features/trees/domain/tree_point.dart';
import 'package:guyub/features/trees/presentation/controllers/tree_point_controller.dart';
import 'package:image/image.dart' as img;

final class _FakeTreePointBoundary implements TreePointBoundary {
  Map<String, Object?>? lastSubmitPayload;
  TreePointSubmissionResult? submitResult;

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
    lastSubmitPayload = {
      'sessionToken': sessionToken,
      'taskId': taskId,
      'speciesHint': speciesHint,
      'exactLat': exactLat,
      'exactLng': exactLng,
      'accuracyMeters': accuracyMeters,
      'isMocked': isMocked,
      'evidenceId': evidenceId,
      'commandId': commandId,
    };
    return submitResult ??
        TreePointSubmissionResult(
          treePointId: 'tp-1',
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

final class _FakeTaskEvidenceBoundary implements TaskEvidenceBoundary {
  Uint8List? uploadedBytes;
  String returnedEvidenceId = 'ev-123';

  @override
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  }) async {
    uploadedBytes = sanitizedJpegBytes;
    return returnedEvidenceId;
  }

  @override
  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  }) async {}

  @override
  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  }) async => Uint8List(0);
}

void main() {
  late _FakeTreePointBoundary boundary;
  late MockDeviceLocationService locationService;
  late _FakeTaskEvidenceBoundary evidenceBoundary;
  late TreePointController controller;

  setUp(() {
    boundary = _FakeTreePointBoundary();
    locationService = MockDeviceLocationService();
    evidenceBoundary = _FakeTaskEvidenceBoundary();
    controller = TreePointController(
      boundary: boundary,
      locationService: locationService,
      evidenceBoundary: evidenceBoundary,
      readSessionToken: () async => 'test-session-token',
      commandIdFactory: () => 'fixed-cmd-123',
    );
  });

  group('TreePointController', () {
    test('rejects mock location before calling boundary', () async {
      final mockedReading = DeviceGpsReading(
        latitude: -8.0,
        longitude: 111.0,
        accuracyMeters: 10.0,
        isMocked: true,
        timestamp: DateTime.now(),
      );

      expect(
        () => controller.submitTreePoint(
          taskId: 'task-1',
          reading: mockedReading,
        ),
        throwsA(isA<TreePointMockLocationException>()),
      );
      expect(boundary.lastSubmitPayload, isNull);
    });

    test('rejects inaccurate GPS (> 30m) before calling boundary', () async {
      final inaccurateReading = DeviceGpsReading(
        latitude: -8.0,
        longitude: 111.0,
        accuracyMeters: 35.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );

      expect(
        () => controller.submitTreePoint(
          taskId: 'task-1',
          reading: inaccurateReading,
        ),
        throwsA(isA<TreePointAccuracyException>()),
      );
      expect(boundary.lastSubmitPayload, isNull);
    });

    test('sanitizes speciesHint before calling boundary', () async {
      final reading = DeviceGpsReading(
        latitude: -8.065432,
        longitude: 111.901234,
        accuracyMeters: 15.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );

      await controller.submitTreePoint(
        taskId: 'task-1',
        speciesHint: '  Pohon Mangga  ',
        reading: reading,
      );

      expect(boundary.lastSubmitPayload?['speciesHint'], 'Pohon Mangga');
      expect(boundary.lastSubmitPayload?['commandId'], 'fixed-cmd-123');
    });

    test('sanitizes and uploads photo evidence when provided', () async {
      final reading = DeviceGpsReading(
        latitude: -8.065432,
        longitude: 111.901234,
        accuracyMeters: 15.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );

      // Create a small valid test jpeg
      final testImg = img.Image(width: 50, height: 50);
      final rawJpeg = Uint8List.fromList(img.encodeJpg(testImg));

      final result = await controller.submitTreePoint(
        taskId: 'task-1',
        speciesHint: 'Mangga',
        reading: reading,
        rawImageBytes: rawJpeg,
      );

      expect(evidenceBoundary.uploadedBytes, isNotNull);
      expect(boundary.lastSubmitPayload?['evidenceId'], 'ev-123');
      expect(result.status, TreePointStatus.pendingVerification);
    });

    test('fails when session token is unavailable', () async {
      final controllerWithoutToken = TreePointController(
        boundary: boundary,
        locationService: locationService,
        readSessionToken: () async => null,
      );

      final reading = DeviceGpsReading(
        latitude: -8.065432,
        longitude: 111.901234,
        accuracyMeters: 15.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );

      expect(
        () => controllerWithoutToken.submitTreePoint(
          taskId: 'task-1',
          reading: reading,
        ),
        throwsA(isA<TreePointException>()),
      );
    });
  });
}
