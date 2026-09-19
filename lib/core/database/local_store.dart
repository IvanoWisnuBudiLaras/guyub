/// Kontrak penyimpanan data lokal pada perangkat pengguna.
///
/// Application dan feature layer menggunakan kontrak ini tanpa mengetahui
/// implementasi database konkret yang digunakan di baliknya.
///
/// Implementasi dapat diganti (misalnya dari SharedPreferences ke Drift/SQLite)
/// pada fase berikutnya tanpa mengubah kode yang mengonsumsi interface ini.
abstract interface class LocalStore {
  /// Menyimpan nilai teks [value] dengan kunci pengenal [key].
  ///
  /// Menimpa nilai lama jika [key] sudah ada sebelumnya.
  Future<void> write(String key, String value);

  /// Membaca nilai yang sebelumnya disimpan pada perangkat.
  ///
  /// Mengembalikan `null` jika [key] belum tersedia di penyimpanan.
  Future<String?> read(String key);

  /// Menghapus pasangan data yang diasosiasikan dengan [key].
  Future<void> delete(String key);

  /// Menghapus seluruh data yang tersimpan di dalam store ini.
  Future<void> clear();

  /// Memeriksa apakah [key] telah tersimpan pada media lokal.
  Future<bool> containsKey(String key);

  /// Menutup atau melepaskan resource penyimpanan jika diperlukan.
  Future<void> close();
}
