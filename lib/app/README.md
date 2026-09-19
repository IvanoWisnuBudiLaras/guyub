# App Layer — Guyub.id

Layer ini bertanggung jawab atas perakitan awal (orchestration) dan daur hidup level teratas aplikasi Flutter.

## Komponen
1. **`app.dart`**: Mendefinisikan root widget `GuyubApp`, konfigurasi Material 3 Theme, dan `FoundationScreen` (smoke screen baseline Phase 0).
2. **`bootstrap.dart`**: Mengorkestrasi startup aplikasi: menginisialisasi Flutter framework binding, menyuntikkan `AppConfig`, dan bootstrap Firebase emulator.
3. **`router.dart`**: Mendefinisikan rute dan routing table aplikasi.

## Larangan Ketat
- **DILARANG** menulis business logic atau state management domain di layer ini.
- **DILARANG** melakukan query data langsung ke database atau API di dalam widget `app.dart`.
- Layer ini hanya berperan sebagai perekat (wiring) antara konfigurasi, navigasi, dan tema global.
