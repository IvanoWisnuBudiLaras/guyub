/// Identity and RT membership for an authenticated community operator.
enum OperatorRole { ketuaRtRw, pendampingRt }

extension OperatorRoleLabel on OperatorRole {
  String get label => switch (this) {
    OperatorRole.ketuaRtRw => 'Ketua RT/RW',
    OperatorRole.pendampingRt => 'Pendamping RT',
  };

  static OperatorRole? fromWireValue(String? value) => switch (value) {
    'KETUA_RT_RW' => OperatorRole.ketuaRtRw,
    'PENDAMPING_RT' => OperatorRole.pendampingRt,
    _ => null,
  };
}

/// Minimal operator profile. Membership is loaded from the trusted RT record.
final class OperatorProfile {
  OperatorProfile({
    required this.uid,
    required this.communityId,
    required this.role,
    required this.displayName,
    this.rtLabel,
    this.communityName,
  }) {
    if (uid.trim().isEmpty ||
        communityId.trim().isEmpty ||
        displayName.trim().isEmpty) {
      throw ArgumentError('Operator identity fields must not be empty.');
    }
  }

  final String uid;
  final String communityId;
  final OperatorRole role;
  final String displayName;
  final String? rtLabel;
  final String? communityName;

  /// Nama komunitas manusiawi untuk badge (menghindari slug mentah seperti rt-01-demo)
  String get humanizedCommunityName {
    if (communityName != null && communityName!.trim().isNotEmpty) {
      return communityName!;
    }
    if (rtLabel != null && rtLabel!.trim().isNotEmpty) {
      return rtLabel!;
    }
    // Jika slug demo (misal "rt-01-demo"), tampilkan nama komunitas dari displayName
    if (communityId.toLowerCase().contains('demo')) {
      final match = RegExp(r'(RT\s*\d+.*)', caseSensitive: false).firstMatch(displayName);
      if (match != null) {
        return match.group(1)!;
      }
      return 'RT 01 Kedungwaru';
    }
    return 'RT $communityId';
  }
}
