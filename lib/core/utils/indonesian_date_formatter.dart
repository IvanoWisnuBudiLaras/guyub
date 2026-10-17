/// Pure-Dart Indonesian date/time formatter.
///
/// Zero extra dependencies. Use this in all display-facing date strings
/// instead of [MaterialLocalizations.formatMediumDate] (which falls back
/// to English when no locale delegate is registered) or raw [DateTime.toString].
abstract final class IndonesianDateFormatter {
  static const _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];
  static const _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  /// Returns "Senin, 19 Oktober 2026 • 15:00 WIB".
  static String formatFull(DateTime dateTime) {
    final local = dateTime.toLocal();
    final dayName = _days[local.weekday - 1];
    final monthName = _months[local.month - 1];
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$dayName, ${local.day} $monthName ${local.year} \u2022 $hour:$minute WIB';
  }

  /// Returns "19 Okt 2026 15:00" — compact form for tables/chips.
  static String formatCompact(DateTime dateTime) {
    final local = dateTime.toLocal();
    final shortMonth = _months[local.month - 1].substring(0, 3);
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day} $shortMonth ${local.year} $hour:$minute';
  }

  /// Returns "19/10/2026 15:00" — numeric short form for logs/audit rows.
  static String formatNumeric(DateTime dateTime) {
    final local = dateTime.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  /// Returns "Senin, 19 Oktober 2026" — date only, no time.
  static String formatDateOnly(DateTime dateTime) {
    final local = dateTime.toLocal();
    final dayName = _days[local.weekday - 1];
    final monthName = _months[local.month - 1];
    return '$dayName, ${local.day} $monthName ${local.year}';
  }
}
