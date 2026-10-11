import 'dart:typed_data';

/// Callable boundary for evidence bytes and private RT review.
///
/// Implementations must not expose public download URLs or queue image bytes
/// for offline retries.
abstract interface class TaskEvidenceBoundary {
  Future<String> uploadResidentTaskEvidence({
    required String sessionToken,
    required String taskId,
    required String requestId,
    required Uint8List sanitizedJpegBytes,
  });

  Future<void> deleteResidentTaskEvidence({
    required String sessionToken,
    required String evidenceId,
    required String commandId,
  });

  Future<Uint8List> getTaskEvidenceForVerification({
    required String evidenceId,
  });
}
