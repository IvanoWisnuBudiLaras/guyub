import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/models/app_session.dart';

/// Menyimpan session (token + info minimal RT) secara lokal & ter-scope.
/// Pakai flutter_secure_storage (bukan shared_preferences) karena ini
/// nyimpen token auth — sesuai prinsip least-privilege di PRD.
///
/// PENTING: hanya simpan field yang ada di AppSession. Jangan tambahkan
/// penyimpanan field lain (nomor HP, alamat, dll) di sini tanpa persetujuan
/// eksplisit — lihat AT-009 & P-01 di TEST_ACCEPTANCE_MATRIX.md.
abstract class SessionStorage {
  Future<void> save(AppSession session);
  Future<AppSession?> read();
  Future<void> clear();
}

class SecureSessionStorage implements SessionStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _key = 'guyub_session';

  @override
  Future<void> save(AppSession session) async {
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  @override
  Future<AppSession?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return AppSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Data korup/format lama — anggap tidak ada sesi, jangan crash.
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
