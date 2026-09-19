import '../result/result.dart';

/// Kontrak boundary komunikasi jaringan eksternal aplikasi Guyub.id.
///
/// Layer aplikasi dan data mengonsumsi kontrak ini untuk berinteraksi dengan API eksternal
/// (seperti Open Data Cuaca BMKG) tanpa bergantung langsung pada package HTTP pihak ketiga
/// (misal `http`, `dio`, dsb).
///
/// Implementasi konkret akan ditambahkan pada Phase 3 (Weather Integration).
abstract interface class NetworkClient {
  /// Mengirimkan permintaan HTTP GET ke [endpoint].
  Future<Result<String>> get(String endpoint, {Map<String, String>? headers});
}
