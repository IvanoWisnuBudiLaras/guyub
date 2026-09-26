import 'weather_snapshot.dart';

/// Ringkasan 3 angka "Tugas Saya" di Beranda Warga (image14 di mockup).
class ResidentTaskStats {
  const ResidentTaskStats({
    required this.inProgress,
    required this.completed,
    required this.notStarted,
  });
  final int inProgress;
  final int completed;
  final int notStarted;
}

/// Card kuning "PRIORITAS — segera diselesaikan" di Beranda Warga.
/// Null kalau nggak ada tugas prioritas aktif.
class PriorityTaskSummary {
  const PriorityTaskSummary({
    required this.title,
    required this.deadlineLabel,
    required this.locationLabel,
  });
  final String title;
  final String deadlineLabel; // "Batas: Besok"
  final String locationLabel;
}

class WargaHomeData {
  const WargaHomeData({
    required this.residentName,
    required this.rtLabel,
    required this.weather,
    required this.stats,
    this.priorityTask,
  });
  final String residentName;
  final String rtLabel; // "RT 03 / RW 07"
  final WeatherSnapshot weather;
  final ResidentTaskStats stats;
  final PriorityTaskSummary? priorityTask;
}

/// Progress "Kesiapan Rumah Tangga" di Beranda Ketua RT (image12).
class HouseholdReadiness {
  const HouseholdReadiness({
    required this.readyCount,
    required this.totalCount,
    required this.targetDateLabel,
  });
  final int readyCount;
  final int totalCount;
  final String targetDateLabel; // "Target: 28 Agustus"

  double get ratio => totalCount == 0 ? 0 : readyCount / totalCount;
  int get percent => (ratio * 100).round();
}

/// Card kuning "Menunggu Verifikasi" di Beranda Ketua RT — completion yang
/// masuk dari warga, status PENDING_VERIFICATION (spec §10.2), belum VERIFIED.
class PendingVerificationItem {
  const PendingVerificationItem({
    required this.taskId,
    required this.residentName,
    required this.taskTitle,
    required this.submittedLabel,
    required this.hasPhoto,
  });
  final String taskId;
  final String residentName;
  final String taskTitle;
  final String submittedLabel; // "15 Ags 2026, 08:15"
  final bool hasPhoto;
}

class ResidentTaskStatsRt {
  const ResidentTaskStatsRt({
    required this.activeTasks,
    required this.completed,
    required this.pending,
  });
  final int activeTasks;
  final int completed;
  final int pending;
}

class RecentTaskSummary {
  const RecentTaskSummary({
    required this.title,
    required this.progressLabel, // "3/14 warga selesai"
    required this.statusLabel, // "Aktif" / "Pending"
  });
  final String title;
  final String progressLabel;
  final String statusLabel;
}

class RtHomeData {
  const RtHomeData({
    required this.operatorName,
    required this.rtLabel,
    required this.weather,
    required this.readiness,
    required this.vulnerableNeedingHelpCount,
    this.pendingVerification,
    required this.stats,
    required this.recentTasks,
  });
  final String operatorName;
  final String rtLabel;
  final WeatherSnapshot weather;
  final HouseholdReadiness readiness;
  final int vulnerableNeedingHelpCount;
  final PendingVerificationItem? pendingVerification;
  final ResidentTaskStatsRt stats;
  final List<RecentTaskSummary> recentTasks;
}
