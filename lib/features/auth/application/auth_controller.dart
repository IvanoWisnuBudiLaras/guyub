import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import 'boundaries/operator_auth_boundary.dart';
import 'boundaries/resident_session_boundary.dart';
import 'state/auth_state.dart';

/// Controller application-layer yang mengorkestrasi seluruh alur masuk
/// (entry) pada fitur Auth untuk kedua jalur peran:
///
/// - **Operator** (Ketua RT/RW, Pendamping RT) melalui Firebase Auth.
/// - **Warga** melalui kode RT yang divalidasi backend (sesi peserta).
///
/// Controller ini **hanya** bergantung pada kontrak boundary, sehingga dapat
/// diuji dengan adapter in-memory/fake tanpa Firebase (isolasi Phase 1).
///
/// **Authorization boundary:** keberhasilan login di sini bukan otorisasi
/// final. Setiap aksi operator tetap diverifikasi server-side (SEC-01).
final class AuthController extends ChangeNotifier {
  final OperatorAuthBoundary _operatorAuth;
  final ResidentSessionBoundary _residentSession;

  AuthState _state = AuthState.initial;

  /// State publik yang dapat dibaca presentation layer.
  AuthState get state => _state;

  AuthController({
    required OperatorAuthBoundary operatorAuth,
    required ResidentSessionBoundary residentSession,
  }) : _operatorAuth = operatorAuth,
       _residentSession = residentSession;

  void _emit(AuthState next) {
    _state = next;
    notifyListeners();
  }

  /// Memulihkan sesi yang tersimpan saat aplikasi dibuka.
  ///
  /// Urutan: cek sesi operator yang sudah login, lalu coba pulihkan sesi
  /// peserta warga. Jika tidak ada keduanya, state menjadi unauthenticated.
  Future<void> initialize() async {
    _emit(_state.copyWith(isBusy: true, clearError: true));

    // 1. Operator: cek sesi Firebase Auth yang sudah ada.
    final operatorResult = await _operatorAuth.currentOperator();
    if (operatorResult.isOk) {
      final profile = operatorResult.dataOrNull;
      if (profile != null) {
        _emit(AuthState.forOperator(profile));
        return;
      }
    }
    // Pemulihan sesi operator gagal: jangan gagalkan startup, lanjut ke warga.

    // 2. Warga: pulihkan sesi peserta tersimpan (jika masih berlaku).
    final residentResult = await _residentSession.restoreSession();
    if (residentResult.isOk) {
      final session = residentResult.dataOrNull;
      if (session != null && !session.isExpiredAt(DateTime.now())) {
        _emit(AuthState.forResident(session));
        return;
      }
      if (session != null) {
        // Sesi kedaluwarsa: bersihkan agar tidak dipakai sebagai valid.
        await _residentSession.clearSession();
      }
    }

    _emit(AuthState.unauthenticated);
  }

  /// Masuk sebagai operator formal menggunakan email dan kata sandi.
  ///
  /// Mengembalikan `true` bila berhasil agar presentation layer dapat
  /// mengarahkan navigasi. Pesan kegagalan bersifat generik (ERR-05).
  Future<bool> signInOperator({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();

    // Validasi bentuk minimal di client; otorisasi tetap di server.
    if (trimmedEmail.isEmpty || password.isEmpty) {
      _emit(
        _state.copyWith(
          isBusy: false,
          errorMessage: 'Email dan kata sandi wajib diisi.',
        ),
      );
      return false;
    }
    if (!_looksLikeEmail(trimmedEmail)) {
      _emit(
        _state.copyWith(
          isBusy: false,
          errorMessage: 'Format email tidak valid.',
        ),
      );
      return false;
    }

    _emit(_state.copyWith(isBusy: true, clearError: true));

    final result = await _operatorAuth.signInWithEmailPassword(
      email: trimmedEmail,
      password: password,
    );

    switch (result) {
      case Success(:final data):
        _emit(AuthState.forOperator(data));
        return true;
      case Failure(:final error):
        _emit(
          _state.copyWith(isBusy: false, errorMessage: error.userMessage),
        );
        return false;
    }
  }

  /// Bergabung sebagai warga menggunakan kode RT (tanpa akun formal).
  ///
  /// Kode divalidasi backend melalui ResidentSessionBoundary. Kegagalan
  /// mengembalikan pesan generik tanpa membocorkan keberadaan RT (ERR-04).
  Future<bool> joinAsResident(String joinCode) async {
    final normalized = _normalizeJoinCode(joinCode);

    if (normalized.isEmpty) {
      _emit(
        _state.copyWith(
          isBusy: false,
          errorMessage: 'Kode RT wajib diisi.',
        ),
      );
      return false;
    }

    _emit(_state.copyWith(isBusy: true, clearError: true));

    final result = await _residentSession.joinWithCode(normalized);

    switch (result) {
      case Success(:final data):
        _emit(AuthState.forResident(data));
        return true;
      case Failure(:final error):
        _emit(
          _state.copyWith(isBusy: false, errorMessage: error.userMessage),
        );
        return false;
    }
  }

  /// Keluar dari sesi aktif (operator maupun warga) dan kembali ke pemilihan peran.
  Future<void> signOut() async {
    _emit(_state.copyWith(isBusy: true, clearError: true));

    if (_state.isResidentSession) {
      await _residentSession.clearSession();
    } else {
      await _operatorAuth.signOut();
    }

    _emit(AuthState.unauthenticated);
  }

  /// Menghapus pesan kesalahan tanpa mengubah status sesi.
  void clearError() {
    if (_state.errorMessage != null) {
      _emit(_state.copyWith(clearError: true));
    }
  }

  static bool _looksLikeEmail(String value) {
    // Pemeriksaan bentuk ringan; validasi otoritatif tetap di Firebase Auth.
    final atIndex = value.indexOf('@');
    return atIndex > 0 &&
        atIndex < value.length - 1 &&
        value.contains('.', atIndex);
  }

  /// Normalisasi kode RT: buang spasi dan jadikan huruf besar.
  ///
  /// Tidak mengubah arti kode; hanya membersihkan input umum (mis. spasi).
  static String _normalizeJoinCode(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}