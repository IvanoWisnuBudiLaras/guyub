import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/core/network/callable_client.dart';
import 'package:guyub/features/trees/application/tree_point_boundary.dart';
import 'package:guyub/features/trees/data/firebase_tree_point_boundary.dart';
import 'package:guyub/features/trees/domain/tree_point.dart';

void main() {
  group('FirebaseTreePointBoundary', () {
    test('submitTreePoint invokes callable and maps response', () async {
      final boundary = FirebaseTreePointBoundary.withInvoker((
        name,
        data,
      ) async {
        expect(name, 'submitTreePoint');
        expect(data['sessionToken'], 'token-123');
        expect(data['taskId'], 'task-456');
        expect(data['speciesHint'], 'Ketapang');
        expect(data['exactLat'], -8.065432);
        expect(data['exactLng'], 111.901234);
        expect(data['accuracyMeters'], 12.5);
        expect(data['isMocked'], false);
        expect(data['commandId'], 'cmd-789');

        return {
          'treePointId': 'tp-999',
          'status': 'PENDING_RT_VERIFICATION',
          'coarseLocation': {
            'cellId': 'qw4z91p',
            'approximateLat': -8.065,
            'approximateLng': 111.901,
          },
          'submittedAt': '2026-10-18T03:00:00.000Z',
        };
      });

      final result = await boundary.submitTreePoint(
        sessionToken: 'token-123',
        taskId: 'task-456',
        speciesHint: 'Ketapang',
        exactLat: -8.065432,
        exactLng: 111.901234,
        accuracyMeters: 12.5,
        isMocked: false,
        commandId: 'cmd-789',
      );

      expect(result.treePointId, 'tp-999');
      expect(result.status, TreePointStatus.pendingVerification);
      expect(result.coarseLocation.cellId, 'qw4z91p');
    });

    test('listCommunityTreeMap maps response items', () async {
      final boundary = FirebaseTreePointBoundary.withInvoker((
        name,
        data,
      ) async {
        expect(name, 'listCommunityTreeMap');
        return {
          'items': [
            {
              'treePointId': 'tp-1',
              'speciesHint': 'Mangga',
              'submitterNickname': 'Budi',
              'isAnonymous': false,
              'coarseLocation': {
                'cellId': 'qw4z91p',
                'approximateLat': -8.065,
                'approximateLng': 111.901,
              },
              'plantedAt': '2026-10-18T03:00:00.000Z',
              'hasEvidencePhoto': true,
            },
          ],
          'totalVerifiedTrees': 1,
        };
      });

      final map = await boundary.listCommunityTreeMap();
      expect(map.totalVerifiedTrees, 1);
      expect(map.items.length, 1);
      expect(map.items.first.submitterNickname, 'Budi');
      expect(map.items.first.hasEvidencePhoto, isTrue);
    });

    test('verifyTreePoint sends approval and maps response', () async {
      final boundary = FirebaseTreePointBoundary.withInvoker((
        name,
        data,
      ) async {
        expect(name, 'verifyTreePoint');
        expect(data['treePointId'], 'tp-1');
        expect(data['decision'], 'APPROVE');
        expect(data['commandId'], 'cmd-1');

        return {
          'treePointId': 'tp-1',
          'status': 'VERIFIED',
          'verifiedAt': '2026-10-18T03:05:00.000Z',
        };
      });

      final result = await boundary.verifyTreePoint(
        treePointId: 'tp-1',
        decision: TreePointDecision.approve,
        commandId: 'cmd-1',
      );

      expect(result.treePointId, 'tp-1');
      expect(result.status, TreePointStatus.verified);
    });

    test('maps failed-precondition GPS accuracy error', () async {
      final boundary = FirebaseTreePointBoundary.withInvoker((
        name,
        data,
      ) async {
        throw const CallableException(
          'failed-precondition',
          'Akurasi GPS tidak memadai (maksimal 30 meter).',
        );
      });

      expect(
        () => boundary.submitTreePoint(
          sessionToken: 'token',
          taskId: 'task',
          exactLat: -8.0,
          exactLng: 111.0,
          accuracyMeters: 45.0,
          isMocked: false,
          commandId: 'cmd',
        ),
        throwsA(isA<TreePointAccuracyException>()),
      );
    });

    test('maps permission-denied mock location error', () async {
      final boundary = FirebaseTreePointBoundary.withInvoker((
        name,
        data,
      ) async {
        throw const CallableException(
          'permission-denied',
          'Lokasi palsu (mock location) terdeteksi.',
        );
      });

      expect(
        () => boundary.submitTreePoint(
          sessionToken: 'token',
          taskId: 'task',
          exactLat: -8.0,
          exactLng: 111.0,
          accuracyMeters: 10.0,
          isMocked: true,
          commandId: 'cmd',
        ),
        throwsA(isA<TreePointMockLocationException>()),
      );
    });
  });
}
