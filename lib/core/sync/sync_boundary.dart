import '../result/result.dart';

/// Kontrak boundary untuk mekanisme sinkronisasi data offline-to-online.
///
/// Dirancang untuk memenuhi invariant PRD §20 (ERR-03) di mana aksi warga yang dilakukan
/// saat offline dimasukkan ke dalam antrean lokal, lalu dikirimkan kembali secara idempoten
/// ke backend saat koneksi internet pulih.
///
/// Implementasi antrean persisten akan dikembangkan pada Phase 2 (Tasks & Offline).
abstract interface class SyncBoundary {
  /// Memasukkan payload mutasi offline ke antrean pengiriman lokal.
  Future<Result<void>> enqueueAction({
    required String actionType,
    required String payloadJson,
  });

  /// Memproses pengiriman seluruh aksi tertunda yang tersimpan di antrean.
  ///
  /// Mengembalikan jumlah aksi yang berhasil disinkronisasi.
  Future<Result<int>> processPendingQueue();
}
