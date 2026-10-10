import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/result/app_error.dart';
import '../../../core/result/result.dart';
import '../application/operator_auth_boundary.dart';
import '../application/operator_profile.dart';

/// Firebase Auth + Firestore adapter for operator sessions.
///
/// Firestore rules must restrict `/operators/{uid}` reads to that authenticated
/// operator and deny all client writes. This adapter is not an authorization
/// substitute; it consumes the server-enforced membership boundary.
final class FirebaseOperatorAuthBoundary implements OperatorAuthBoundary {
  FirebaseOperatorAuthBoundary({required this.auth, required this.firestore});

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  static const _genericAuthMessage =
      'Tidak dapat masuk. Periksa email, kata sandi, atau status akses operator.';

  @override
  Future<Result<OperatorProfile>> signIn({
    required String email,
    required String password,
  }) async {
    if (email.trim().isEmpty || password.isEmpty) {
      return const Result.err(
        ValidationError(message: 'Email dan kata sandi wajib diisi.'),
      );
    }
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return const Result.err(AuthError(message: _genericAuthMessage));
      }

      final profile = await _readActiveMembership(user.uid);
      if (profile == null) {
        await _signOutQuietly();
        return const Result.err(AuthError(message: _genericAuthMessage));
      }
      return Result.ok(profile);
    } on FirebaseException catch (error) {
      await _signOutQuietly();
      if (_isNetworkFailure(error.code)) {
        return const Result.err(
          NetworkError(
            message: 'Koneksi tidak tersedia. Coba lagi saat tersambung.',
          ),
        );
      }
      return const Result.err(AuthError(message: _genericAuthMessage));
    } catch (_) {
      await _signOutQuietly();
      return const Result.err(AuthError(message: _genericAuthMessage));
    }
  }

  @override
  Future<Result<OperatorProfile>> restoreCurrentSession() async {
    final user = auth.currentUser;
    if (user == null) return const Result.err(AuthError());
    try {
      final profile = await _readActiveMembership(user.uid);
      if (profile == null) {
        await _signOutQuietly();
        return const Result.err(AuthError());
      }
      return Result.ok(profile);
    } on FirebaseException catch (error) {
      if (_isNetworkFailure(error.code)) {
        return const Result.err(
          NetworkError(
            message: 'Koneksi tidak tersedia. Periksa kembali saat daring.',
          ),
        );
      }
      await _signOutQuietly();
      return const Result.err(AuthError());
    } catch (_) {
      await _signOutQuietly();
      return const Result.err(AuthError());
    }
  }

  Future<OperatorProfile?> _readActiveMembership(String uid) async {
    final document = await firestore
        .collection('operators')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    final data = document.data();
    if (!document.exists || data == null || data['active'] != true) return null;

    final role = OperatorRoleLabel.fromWireValue(data['role'] as String?);
    final communityId = data['rtId'] as String?;
    final displayName = data['displayName'] as String?;
    if (role == null || communityId == null || displayName == null) return null;
    try {
      return OperatorProfile(
        uid: uid,
        communityId: communityId,
        role: role,
        displayName: displayName,
      );
    } on ArgumentError {
      return null;
    }
  }

  Future<void> _signOutQuietly() async {
    try {
      await auth.signOut();
    } catch (_) {
      // Authorization still fails closed even if local sign-out reports an error.
    }
  }

  bool _isNetworkFailure(String code) =>
      code == 'unavailable' ||
      code == 'deadline-exceeded' ||
      code == 'network-request-failed';

  @override
  Future<void> signOut() => auth.signOut();
}
