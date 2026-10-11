# Feature: Evidence (Bukti Foto Persiapan)

Bukti foto bersifat opsional. Foto tidak boleh menggagalkan penyelesaian tugas.

**Status:** Pipeline bukti privat diimplementasikan dan diuji pada emulator; bucket dan job produksi belum dikonfigurasi atau dideploy.

## Implemented
- Flutter menulis ulang JPEG untuk menghapus metadata; Cloud Functions memvalidasi dan mengodekan ulang gambar sebelum penyimpanan.
- Upload hanya lewat callable dengan sesi warga yang divalidasi dan respons JOINED untuk tugas aktif.
- Storage dan Firestore menolak akses langsung klien. Tidak ada URL publik atau signed URL.
- Warga dapat menghapus bukti miliknya melalui sesi pada perangkat yang sama. Cleanup idempotent menghapus objek berumur lebih dari 30 hari dan dapat mencoba ulang kegagalan.
- Unit dan Functions/Storage Emulator CI menguji sanitasi, batas akses, penghapusan, dan retry.

## Belum tersedia / manual-eksternal
- Penghapusan seluruh profil, proposal, dan respons warga belum tersedia.
- Proses penghapusan warga melalui RT untuk perangkat hilang menunggu prosedur verifikasi identitas yang disetujui.
- Bucket Storage, scheduled cleanup, kredensial, dan deployment produksi belum dikonfigurasi. Tidak ada billing yang diaktifkan.

## Invariants
- Foto bersifat opsional; kegagalan upload tidak memblokir penyelesaian tugas (ERR-06).
- Metadata lokasi (EXIF GPS) dibersihkan sebelum penyimpanan (AT-010, P-02).
- Bukti dihapus setelah 30 hari; kegagalan terdeteksi dan dapat dicoba ulang (AT-011, P-03, SEC-09).
