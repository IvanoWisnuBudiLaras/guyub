/// Informasi minima sesi warga. Token rahasia sengaja tidak menjadi bagian model UI.
final class ResidentSession {
  const ResidentSession({
    required this.residentId,
    required this.communityId,
    required this.communityName,
    required this.rtLabel,
    required this.nickname,
    required this.expiresAt,
  });

  final String residentId;
  final String communityId;
  final String communityName;
  final String rtLabel;
  final String nickname;
  final DateTime expiresAt;

  @override
  bool operator ==(Object other) =>
      other is ResidentSession &&
      other.residentId == residentId &&
      other.communityId == communityId &&
      other.communityName == communityName &&
      other.rtLabel == rtLabel &&
      other.nickname == nickname &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(
    residentId,
    communityId,
    communityName,
    rtLabel,
    nickname,
    expiresAt,
  );
}

/// Sesi terverifikasi dan token opaque yang hanya boleh masuk ke secure storage.
final class ResidentSessionGrant {
  const ResidentSessionGrant({
    required this.session,
    required this.sessionToken,
  });

  final ResidentSession session;
  final String sessionToken;
}
