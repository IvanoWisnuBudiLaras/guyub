import '../models/home_data.dart';

/// Kontrak data untuk Beranda Warga (SCR-03) & Beranda Ketua RT (SCR-08).
/// Fake dulu — nanti diganti agregasi dari task_campaigns, task_responses,
/// weather_snapshots, dst (spec §12), tidak akan ada 1 collection "home".
abstract class HomeRepository {
  Future<WargaHomeData> getWargaHome();
  Future<RtHomeData> getRtHome();
}
