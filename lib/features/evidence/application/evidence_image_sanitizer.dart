import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Re-encodes resident evidence as bounded JPEG bytes without image metadata.
/// The caller must upload only these bytes, never the source file.
final class EvidenceImageSanitizer {
  const EvidenceImageSanitizer._();

  static const int maxInputBytes = 8 * 1024 * 1024;
  static const int maxOutputBytes = 2 * 1024 * 1024;
  static const int maxImagePixels = 12 * 1000 * 1000;
  static const int maxDimension = 1280;
  static const List<int> _jpegQualities = [82, 74, 66, 58];

  static SanitizedEvidenceImage sanitize(Uint8List sourceBytes) {
    if (sourceBytes.isEmpty ||
        sourceBytes.length > maxInputBytes ||
        sourceBytes.length < 4) {
      throw const EvidenceImageSanitizationException();
    }

    try {
      final decoder = image.JpegDecoder();
      final info = decoder.startDecode(sourceBytes);
      if (info == null || info.width <= 0 || info.height <= 0) {
        throw const EvidenceImageSanitizationException();
      }
      if (info.width * info.height > maxImagePixels) {
        throw const EvidenceImageSanitizationException();
      }

      final decoded = decoder.decode(sourceBytes);
      if (decoded == null) throw const EvidenceImageSanitizationException();

      final oriented = image.bakeOrientation(decoded);
      final scale = math.min(
        1.0,
        maxDimension / math.max(oriented.width, oriented.height),
      );
      final targetWidth = (oriented.width * scale).round().clamp(
        1,
        maxDimension,
      );
      final targetHeight = (oriented.height * scale).round().clamp(
        1,
        maxDimension,
      );
      final resized =
          targetWidth == oriented.width && targetHeight == oriented.height
          ? oriented
          : image.copyResize(
              oriented,
              width: targetWidth,
              height: targetHeight,
              maintainAspect: false,
              interpolation: image.Interpolation.average,
            );

      // Create a new pixel-only image. Resize/copy operations can retain EXIF,
      // ICC, comments, or text fields from their input.
      final pixelsOnly = image.Image(
        width: resized.width,
        height: resized.height,
        numChannels: 3,
      );
      for (final pixel in resized) {
        pixelsOnly.setPixelRgb(pixel.x, pixel.y, pixel.r, pixel.g, pixel.b);
      }

      for (final quality in _jpegQualities) {
        final sanitizedBytes = image.encodeJpg(pixelsOnly, quality: quality);
        if (sanitizedBytes.length <= maxOutputBytes) {
          return SanitizedEvidenceImage._(
            bytes: sanitizedBytes,
            width: pixelsOnly.width,
            height: pixelsOnly.height,
          );
        }
      }
      throw const EvidenceImageSanitizationException();
    } on EvidenceImageSanitizationException {
      rethrow;
    } catch (_) {
      throw const EvidenceImageSanitizationException();
    }
  }
}

final class SanitizedEvidenceImage {
  const SanitizedEvidenceImage._({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  String get mimeType => 'image/jpeg';
}

/// The source file was invalid or exceeded the safe processing bounds.
final class EvidenceImageSanitizationException implements Exception {
  const EvidenceImageSanitizationException();
}
