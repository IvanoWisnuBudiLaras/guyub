import 'package:shared_preferences/shared_preferences.dart';

import 'local_store.dart';

/// Implementasi [LocalStore] berbasis plugin [SharedPreferences] perangkat.
///
/// Digunakan pada runtime perangkat Android dan iOS untuk menyimpan konfigurasi
/// sesi, snapshot cuaca terakhir, dan cache data persiapan warga secara offline.
final class SharedPrefsLocalStore implements LocalStore {
  final SharedPreferences _prefs;

  const SharedPrefsLocalStore(this._prefs);

  /// Factory asynchronous untuk menginisialisasi store dari runtime OS.
  static Future<SharedPrefsLocalStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsLocalStore(prefs);
  }

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<String?> read(String key) async {
    return _prefs.getString(key);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }

  @override
  Future<void> clear() async {
    await _prefs.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    return _prefs.containsKey(key);
  }

  @override
  Future<void> close() async {
    // SharedPreferences adalah persistent OS resource; tidak memerlukan teardown eksplisit.
  }
}
