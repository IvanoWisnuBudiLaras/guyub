import '../../domain/models/home_data.dart';
import '../../domain/models/weather_snapshot.dart';
import '../../domain/repositories/home_repository.dart';

class FakeHomeRepository implements HomeRepository {
  WeatherSnapshot _sharedWeather() => WeatherSnapshot(
        condition: 'Hujan Sedang',
        temperatureC: 27,
        humidityPercent: 84,
        rainfallMm: 12,
        windKmh: 18,
        observedAt: DateTime.now().subtract(const Duration(minutes: 15)),
        isStale: false,
      );

  @override
  Future<WargaHomeData> getWargaHome() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return WargaHomeData(
      residentName: 'Pak Joko',
      rtLabel: 'RT 03 / RW 07',
      weather: _sharedWeather(),
      stats: const ResidentTaskStats(inProgress: 1, completed: 4, notStarted: 2),
      priorityTask: const PriorityTaskSummary(
        title: 'Cek & lapor kondisi pintu air depan rumah',
        deadlineLabel: 'Batas: Besok',
        locationLabel: 'Jl. Ahmad Yani No. 12',
      ),
    );
  }

  @override
  Future<RtHomeData> getRtHome() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return RtHomeData(
      operatorName: 'Pak Hendra',
      rtLabel: 'RT 03 / RW 07',
      weather: _sharedWeather(),
      readiness: const HouseholdReadiness(
        readyCount: 14,
        totalCount: 32,
        targetDateLabel: 'Target: 28 Agustus',
      ),
      vulnerableNeedingHelpCount: 3,
      pendingVerification: const PendingVerificationItem(
        taskId: 'task-eval-1',
        residentName: 'Bu Sari',
        taskTitle: 'Periksa Jalur Evakuasi',
        submittedLabel: '15 Ags 2026, 08:15',
        hasPhoto: true,
      ),
      stats: const ResidentTaskStatsRt(activeTasks: 5, completed: 12, pending: 3),
      recentTasks: const [
        RecentTaskSummary(
          title: 'Cek pintu air Blok A',
          progressLabel: '8/14 warga selesai',
          statusLabel: 'Aktif',
        ),
        RecentTaskSummary(
          title: 'Distribusi karung pasir RT03',
          progressLabel: '2/14 warga selesai',
          statusLabel: 'Pending',
        ),
      ],
    );
  }
}
