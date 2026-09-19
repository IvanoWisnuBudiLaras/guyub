# Core Layer — Guyub.id

Folder ini berisi fondasi cross-cutting yang bersifat domain-agnostic dan esensial bagi kelangsungan seluruh aplikasi.

## Fungsi Core
Menyediakan kontrak dasar, tipe domain error/result, konfigurasi runtime, abstraksi penyimpanan lokal, komunikasi jaringan, serta mekanisme sinkronisasi data yang decoupled dari library atau provider pihak ketiga.

## Apa yang Layak Masuk Core?
1. **Config (`core/config/`)**: Representasi lingkungan eksekusi (`AppEnvironment`) dan nilai konfigurasi runtime (`AppConfig`).
2. **Result (`core/result/`)**: Tipe kontainer monadik `Result<T>` (`Success`, `Failure`) dan hierarki kesalahan `AppError`.
3. **Database (`core/database/`)**: Kontrak penyimpanan persisten lokal (`LocalStore`) serta implementasi adapter (`SharedPrefsLocalStore`, `InMemoryLocalStore`).
4. **Network (`core/network/`)**: Kontrak boundary HTTP client untuk integrasi remote data.
5. **Sync (`core/sync/`)**: Kontrak boundary antrean sinkronisasi offline-ke-online idempoten.

## Larangan: Core Bukan "Tempat Sampah"
- **DILARANG** meletakkan business logic spesifik fitur di sini (misal validasi tugas banjir, parsing data cuaca BMKG, otentikasi RT). Logic tersebut wajib berada di `lib/features/<nama_feature>/`.
- **DILARANG** meletakkan UI Screen, Dialog, atau Widget spesifik fitur.
- **DILARANG** membocorkan SDK eksternal langsung (Firebase SDK, Dio, Drift) ke kontrak core. Semua dependensi infrastruktur harus berada di balik interface adapter.
- Hanya kode utilitas yang benar-benar dipakai oleh lebih dari dua fitur independen dan tidak memiliki dependensi bisnis yang boleh berada di core.
