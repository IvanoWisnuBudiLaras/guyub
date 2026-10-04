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
}
