/// Informasi minima sesi warga. Token rahasia sengaja tidak menjadi bagian model UI.
final class ResidentSession {
  const ResidentSession({
    required this.residentId,
    required this.communityId,
    required this.communityName,
    required this.rtLabel,
    required this.nickname,
    required this.expiresAt,
    this.isOfflineSnapshot = false,
  });

  final String residentId;
  final String communityId;
  final String communityName;
  final String rtLabel;
  final String nickname;
  final DateTime expiresAt;

  /// True when this profile came from secure local metadata after transport loss.
  /// It is presentation context only and never authorizes a backend call.
  final bool isOfflineSnapshot;

  ResidentSession asOfflineSnapshot() => ResidentSession(
    residentId: residentId,
    communityId: communityId,
    communityName: communityName,
    rtLabel: rtLabel,
    nickname: nickname,
    expiresAt: expiresAt,
    isOfflineSnapshot: true,
  );

  @override
  bool operator ==(Object other) =>
      other is ResidentSession &&
      other.residentId == residentId &&
      other.communityId == communityId &&
      other.communityName == communityName &&
      other.rtLabel == rtLabel &&
      other.nickname == nickname &&
      other.expiresAt == expiresAt &&
      other.isOfflineSnapshot == isOfflineSnapshot;

  @override
  int get hashCode => Object.hash(
    residentId,
    communityId,
    communityName,
    rtLabel,
    nickname,
    expiresAt,
    isOfflineSnapshot,
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
