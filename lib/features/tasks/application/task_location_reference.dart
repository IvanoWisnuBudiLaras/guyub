/// Coarse, non-address location categories for task campaigns.
///
/// Free text is intentionally not supported until RT-scoped safe locations are
/// provisioned and reviewed.
abstract final class TaskLocationReferences {
  static const allowed = <String>{'COMMUNITY_GENERAL_AREA', 'HOUSEHOLD'};

  static String label(String value) => switch (value) {
    'COMMUNITY_GENERAL_AREA' => 'Area umum RT yang ditentukan operator',
    'HOUSEHOLD' => 'Rumah masing-masing',
    _ => throw ArgumentError.value(
      value,
      'value',
      'Unknown location reference.',
    ),
  };
}
