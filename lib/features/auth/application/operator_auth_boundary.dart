import '../../../core/result/result.dart';
import 'operator_profile.dart';

/// Authentication and membership boundary for RT/RW operators.
abstract interface class OperatorAuthBoundary {
  /// Signs in with Firebase email/password and resolves active RT membership.
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  });

  /// Restores a persisted Firebase session only after membership is rechecked.
  Future<Result<OperatorProfile>> restoreCurrentSession();

  /// Signs the current operator out on this device.
  Future<void> signOut();
}
