# Features Layer — Guyub.id

Folder ini mengelompokkan kode aplikasi menggunakan pendekatan **Decoupled Feature-First Layered Monolith**. Setiap subfolder mewakili satu domain kapabilitas pengguna/sistem.

## Pola Layer di Dalam Setiap Feature
Saat fitur diimplementasikan pada Phase 1+, struktur internalnya menerapkan pemisahan tugas ringan:

```text
features/<nama_feature>/
├── presentation/   # UI widgets, screens, controllers/notifiers
├── application/    # Services, business logic, workflows, state
└── data/           # Repositories, local/remote data sources, models/DTOs
```

## Aturan Dependensi (Dependency Rules)
1. **Unidirectional flow**: `presentation` bergantung pada `application`, `application` bergantung pada `repository/boundary` kontrak, dan `data` mengimplementasikan kontrak tersebut.
2. **Isolasi UI**: Widget UI tidak boleh mengimpor library database (SQLite/Drift) atau Firebase SDK secara langsung. Semua akses data wajib melewati repository.
3. **Komunikasi Antar-Fitur**: Fitur tidak boleh mengakses file internal private milik fitur lain secara acak. Akses silang fitur harus melalui API/Service publik yang didefinisikan secara eksplisit.
4. **Core Utility**: Fitur bebas mengonsumsi kontrak dan utilitas dari `lib/core/` (`Result`, `AppError`, `LocalStore`, `AppConfig`).

## Cara Membuat Fitur Baru
1. Buat folder baru di bawah `lib/features/<nama_fitur>/`.
2. Buat `README.md` yang merujuk pada `FR-*` dan `AT-*` terkait dari Master PRD.
3. Mulai dari kontrak data / state application terlebih dahulu sebelum membuat widget presentation.
