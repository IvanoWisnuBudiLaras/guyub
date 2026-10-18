import 'package:flutter_test/flutter_test.dart';
import 'package:guyub/features/trees/domain/tree_point.dart';

void main() {
  group('TreePointStatus', () {
    test('wire serialization and deserialization match specifications', () {
      expect(TreePointStatus.fromWire('VERIFIED'), TreePointStatus.verified);
      expect(TreePointStatus.fromWire('REJECTED'), TreePointStatus.rejected);
      expect(
        TreePointStatus.fromWire('PENDING_RT_VERIFICATION'),
        TreePointStatus.pendingVerification,
      );
      expect(
        TreePointStatus.fromWire('UNKNOWN'),
        TreePointStatus.pendingVerification,
      );

      expect(TreePointStatus.verified.toWire(), 'VERIFIED');
      expect(TreePointStatus.rejected.toWire(), 'REJECTED');
      expect(
        TreePointStatus.pendingVerification.toWire(),
        'PENDING_RT_VERIFICATION',
      );
    });

    test('indonesian labels are human-friendly', () {
      expect(TreePointStatus.verified.indonesianLabel, 'Terverifikasi RT');
      expect(TreePointStatus.rejected.indonesianLabel, 'Ditolak RT');
      expect(
        TreePointStatus.pendingVerification.indonesianLabel,
        'Menunggu Verifikasi RT',
      );
    });
  });

  group('CoarseLocation', () {
    test('serializes and deserializes accurately', () {
      final coarse = CoarseLocation.fromMap({
        'cellId': 'qw4z91p',
        'approximateLat': -8.065,
        'approximateLng': 111.901,
      });

      expect(coarse.cellId, 'qw4z91p');
      expect(coarse.approximateLat, -8.065);
      expect(coarse.approximateLng, 111.901);

      final map = coarse.toMap();
      expect(map['cellId'], 'qw4z91p');
      expect(map['approximateLat'], -8.065);
      expect(map['approximateLng'], 111.901);
    });
  });

  group('TreePoint entity', () {
    test('displaySubmitterName respects anonymous flag (INV-05)', () {
      final publicTree = TreePoint(
        treePointId: 'tp-1',
        rtId: 'rt-1',
        taskId: 'task-1',
        residentId: 'res-1',
        submitterNickname: 'Pak Budi',
        plantedAt: DateTime.utc(2026, 10, 18),
        status: TreePointStatus.verified,
        coarseLocation: const CoarseLocation(
          cellId: 'qw4z91p',
          approximateLat: -8.065,
          approximateLng: 111.901,
        ),
        isAnonymous: false,
      );
      expect(publicTree.displaySubmitterName, 'Pak Budi');

      final anonymizedTree = TreePoint(
        treePointId: 'tp-2',
        rtId: 'rt-1',
        taskId: 'task-1',
        residentId: 'res-2',
        submitterNickname: 'Pak Budi',
        plantedAt: DateTime.utc(2026, 10, 18),
        status: TreePointStatus.verified,
        coarseLocation: const CoarseLocation(
          cellId: 'qw4z91p',
          approximateLat: -8.065,
          approximateLng: 111.901,
        ),
        isAnonymous: true,
      );
      expect(anonymizedTree.displaySubmitterName, 'Pohon Warga (Anonim)');
    });
  });

  group('DeviceGpsReading', () {
    test('accuracy threshold <= 30 meters is strictly enforced', () {
      final accurate = DeviceGpsReading(
        latitude: -8.065,
        longitude: 111.901,
        accuracyMeters: 29.9,
        isMocked: false,
        timestamp: DateTime.now(),
      );
      expect(accurate.isAcceptableAccuracy, isTrue);
      expect(accurate.isValid, isTrue);

      final boundary = DeviceGpsReading(
        latitude: -8.065,
        longitude: 111.901,
        accuracyMeters: 30.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );
      expect(boundary.isAcceptableAccuracy, isTrue);
      expect(boundary.isValid, isTrue);

      final inaccurate = DeviceGpsReading(
        latitude: -8.065,
        longitude: 111.901,
        accuracyMeters: 30.1,
        isMocked: false,
        timestamp: DateTime.now(),
      );
      expect(inaccurate.isAcceptableAccuracy, isFalse);
      expect(inaccurate.isValid, isFalse);
    });

    test('mock location is rejected', () {
      final mocked = DeviceGpsReading(
        latitude: -8.065,
        longitude: 111.901,
        accuracyMeters: 10.0,
        isMocked: true,
        timestamp: DateTime.now(),
      );
      expect(mocked.isAcceptableAccuracy, isTrue);
      expect(mocked.isValid, isFalse);
    });

    test('coordinate bounds are validated', () {
      final invalidLat = DeviceGpsReading(
        latitude: 91.0,
        longitude: 111.901,
        accuracyMeters: 10.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );
      expect(invalidLat.isValid, isFalse);

      final invalidLng = DeviceGpsReading(
        latitude: -8.065,
        longitude: 181.0,
        accuracyMeters: 10.0,
        isMocked: false,
        timestamp: DateTime.now(),
      );
      expect(invalidLng.isValid, isFalse);
    });
  });

  group('TreePointValidation', () {
    test('sanitizes valid species hint', () {
      expect(
        TreePointValidation.validateSpeciesHint('  Mangga Arumanis  '),
        'Mangga Arumanis',
      );
      expect(TreePointValidation.validateSpeciesHint(null), isNull);
      expect(TreePointValidation.validateSpeciesHint('   '), isNull);
    });

    test('rejects species hint exceeding 60 characters', () {
      final longText = 'A' * 61;
      expect(
        () => TreePointValidation.validateSpeciesHint(longText),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects species hint containing NIK (16 digits)', () {
      expect(
        () => TreePointValidation.validateSpeciesHint(
          'Pohon Mangga 3201012345678901',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('NIK'),
          ),
        ),
      );
    });

    test('rejects species hint containing phone numbers', () {
      expect(
        () => TreePointValidation.validateSpeciesHint(
          'Pohon Jeruk hubungi 081234567890',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('nomor telepon'),
          ),
        ),
      );
    });

    test('rejects species hint containing coordinate strings', () {
      expect(
        () => TreePointValidation.validateSpeciesHint(
          'Pohon di koordinat -8.065432, 111.901234',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('koordinat'),
          ),
        ),
      );
    });
  });
}
