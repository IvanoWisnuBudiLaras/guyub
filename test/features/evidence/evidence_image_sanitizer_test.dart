import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:guyub/features/evidence/application/evidence_image_sanitizer.dart';

void main() {
  test('re-encodes a geotagged JPEG without EXIF or GPS data', () {
    final original = image.Image(width: 24, height: 16, numChannels: 3);
    for (final pixel in original) {
      original.setPixelRgb(pixel.x, pixel.y, 40, 90, 130);
    }
    final exif = image.ExifData();
    exif.gpsIfd[0x0000] = image.IfdByteValue.list(
      Uint8List.fromList([2, 3, 0, 0]),
    );
    exif.gpsIfd[0x0001] = image.IfdValueAscii('N');
    exif.gpsIfd[0x0002] = image.IfdValueRational.list([
      image.IfdValueRational(1, 1).value.single,
      image.IfdValueRational(2, 1).value.single,
      image.IfdValueRational(3, 1).value.single,
    ]);
    exif.gpsIfd[0x0003] = image.IfdValueAscii('E');
    exif.gpsIfd[0x0004] = image.IfdValueRational.list([
      image.IfdValueRational(4, 1).value.single,
      image.IfdValueRational(5, 1).value.single,
      image.IfdValueRational(6, 1).value.single,
    ]);
    final source = image.injectJpgExif(image.encodeJpg(original), exif)!;
    final sourceExif = image.decodeJpgExif(source)!;
    expect(sourceExif.gpsIfd.containsKey(0x0002), isTrue);
    expect(sourceExif.gpsIfd.containsKey(0x0004), isTrue);

    final sanitized = EvidenceImageSanitizer.sanitize(source);

    expect(sanitized.mimeType, 'image/jpeg');
    expect(sanitized.width, 24);
    expect(sanitized.height, 16);
    expect(
      sanitized.bytes.length,
      lessThanOrEqualTo(EvidenceImageSanitizer.maxOutputBytes),
    );
    expect(image.decodeJpgExif(sanitized.bytes), isNull);
    expect(image.decodeJpg(sanitized.bytes), isNotNull);
  });

  test('resizes large images without changing their aspect ratio', () {
    final source = image.Image(width: 1600, height: 800, numChannels: 3);
    for (final pixel in source) {
      source.setPixelRgb(pixel.x, pixel.y, 25, 55, 85);
    }

    final sanitized = EvidenceImageSanitizer.sanitize(image.encodeJpg(source));

    expect(sanitized.width, EvidenceImageSanitizer.maxDimension);
    expect(sanitized.height, EvidenceImageSanitizer.maxDimension ~/ 2);
  });

  test('rejects non-JPEG, empty, and oversized source bytes', () {
    expect(
      () => EvidenceImageSanitizer.sanitize(Uint8List(0)),
      throwsA(isA<EvidenceImageSanitizationException>()),
    );
    expect(
      () => EvidenceImageSanitizer.sanitize(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<EvidenceImageSanitizationException>()),
    );
    expect(
      () => EvidenceImageSanitizer.sanitize(
        Uint8List(EvidenceImageSanitizer.maxInputBytes + 1),
      ),
      throwsA(isA<EvidenceImageSanitizationException>()),
    );
  });
}
