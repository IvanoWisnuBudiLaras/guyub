import 'local_store.dart';

/// Implementasi [LocalStore] berbasis memory (RAM) menggunakan `Map<String, String>`.
///
/// Digunakan secara eksklusif pada unit testing, widget testing, dan lingkungan
/// isolasi agar pengujian berjalan cepat tanpa ketergantungan plugin OS native.
final class InMemoryLocalStore implements LocalStore {
  final Map<String, String> _storage = {};
  bool _isClosed = false;

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError(
        'InMemoryLocalStore telah ditutup dan tidak dapat digunakan.',
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _ensureOpen();
    _storage[key] = value;
  }

  @override
  Future<String?> read(String key) async {
    _ensureOpen();
    return _storage[key];
  }

  @override
  Future<void> delete(String key) async {
    _ensureOpen();
    _storage.remove(key);
  }

  @override
  Future<void> clear() async {
    _ensureOpen();
    _storage.clear();
  }

  @override
  Future<bool> containsKey(String key) async {
    _ensureOpen();
    return _storage.containsKey(key);
  }

  @override
  Future<void> close() async {
    _isClosed = true;
    _storage.clear();
  }
}
