/// The only directory states the backend may return.
enum EmergencyDirectoryStatus { active, disabled, unconfigured }

/// A normalized response from the `getEmergencyDirectory` callable.
///
/// Use [fromWire] at the network boundary. It rejects incomplete, mistyped, or
/// unsupported fields so malformed server data can never replace an offline
/// snapshot.
final class EmergencyDirectoryResponse {
  const EmergencyDirectoryResponse._({
    required this.status,
    required this.version,
    required this.lastVerifiedAt,
    required this.emergencyContacts,
    required this.assemblyPoints,
    required this.officialReportChannels,
  });

  final EmergencyDirectoryStatus status;
  final int? version;
  final DateTime? lastVerifiedAt;
  final List<EmergencyContact> emergencyContacts;
  final List<EmergencyAssemblyPoint> assemblyPoints;
  final List<OfficialReportChannel> officialReportChannels;

  factory EmergencyDirectoryResponse.fromWire(Object? raw, {DateTime? now}) {
    final verificationTime = (now ?? DateTime.now()).toUtc();
    final wire = _wireMap(raw, 'emergency directory');
    final state = wire['state'];
    if (state == 'UNCONFIGURED') {
      _expectKeys(wire, const {'state'}, const {});
      return const EmergencyDirectoryResponse._(
        status: EmergencyDirectoryStatus.unconfigured,
        version: null,
        lastVerifiedAt: null,
        emergencyContacts: [],
        assemblyPoints: [],
        officialReportChannels: [],
      );
    }
    if (state == 'DISABLED') {
      _expectKeys(wire, const {'state', 'version', 'lastVerifiedAt'}, const {});
      return EmergencyDirectoryResponse._(
        status: EmergencyDirectoryStatus.disabled,
        version: _positiveVersion(wire['version']),
        lastVerifiedAt: _requiredDate(
          wire['lastVerifiedAt'],
          'lastVerifiedAt',
          verificationTime,
        ),
        emergencyContacts: const [],
        assemblyPoints: const [],
        officialReportChannels: const [],
      );
    }
    if (state == 'ACTIVE') {
      _expectKeys(wire, const {
        'state',
        'version',
        'lastVerifiedAt',
        'emergencyContacts',
        'assemblyPoints',
        'officialReportChannels',
      }, const {});
      return EmergencyDirectoryResponse._(
        status: EmergencyDirectoryStatus.active,
        version: _positiveVersion(wire['version']),
        lastVerifiedAt: _requiredDate(
          wire['lastVerifiedAt'],
          'lastVerifiedAt',
          verificationTime,
        ),
        emergencyContacts: _contacts(wire['emergencyContacts']),
        assemblyPoints: _assemblyPoints(wire['assemblyPoints']),
        officialReportChannels: _reportChannels(wire['officialReportChannels']),
      );
    }
    throw const FormatException('Invalid emergency directory state.');
  }

  /// Wire form used only for cache serialization and callable parsing tests.
  Map<String, Object?> toWire() {
    switch (status) {
      case EmergencyDirectoryStatus.unconfigured:
        return const {'state': 'UNCONFIGURED'};
      case EmergencyDirectoryStatus.disabled:
        return {
          'state': 'DISABLED',
          'version': version,
          'lastVerifiedAt': lastVerifiedAt!.toUtc().toIso8601String(),
        };
      case EmergencyDirectoryStatus.active:
        return {
          'state': 'ACTIVE',
          'version': version,
          'lastVerifiedAt': lastVerifiedAt!.toUtc().toIso8601String(),
          'emergencyContacts': emergencyContacts
              .map((item) => item.toWire())
              .toList(growable: false),
          'assemblyPoints': assemblyPoints
              .map((item) => item.toWire())
              .toList(growable: false),
          'officialReportChannels': officialReportChannels
              .map((item) => item.toWire())
              .toList(growable: false),
        };
    }
  }

  /// Directory content is revisioned independently of when an operator last
  /// verified it. A verification timestamp change alone is not a data conflict.
  bool hasSameDirectoryData(EmergencyDirectoryResponse other) {
    if (status != other.status ||
        !_sameList(emergencyContacts, other.emergencyContacts) ||
        !_sameList(assemblyPoints, other.assemblyPoints) ||
        !_sameList(officialReportChannels, other.officialReportChannels)) {
      return false;
    }
    return true;
  }
}

final class EmergencyContact {
  const EmergencyContact({required this.label, required this.phone});

  final String label;
  final String phone;

  factory EmergencyContact.fromWire(Object? raw) {
    final wire = _wireMap(raw, 'emergency contact');
    _expectKeys(wire, const {'label', 'phone'}, const {});
    return EmergencyContact(
      label: _cleanText(wire['label'], 'contact label', 80),
      phone: _validPhone(wire['phone'], 'contact phone'),
    );
  }

  Map<String, Object?> toWire() => {'label': label, 'phone': phone};

  @override
  bool operator ==(Object other) =>
      other is EmergencyContact && other.label == label && other.phone == phone;

  @override
  int get hashCode => Object.hash(label, phone);
}

final class EmergencyAssemblyPoint {
  const EmergencyAssemblyPoint({
    required this.label,
    required this.publicLocation,
  });

  final String label;
  final String publicLocation;

  factory EmergencyAssemblyPoint.fromWire(Object? raw) {
    final wire = _wireMap(raw, 'assembly point');
    _expectKeys(wire, const {'label', 'publicLocation'}, const {});
    return EmergencyAssemblyPoint(
      label: _cleanText(wire['label'], 'assembly point label', 80),
      publicLocation: _cleanText(wire['publicLocation'], 'publicLocation', 240),
    );
  }

  Map<String, Object?> toWire() => {
    'label': label,
    'publicLocation': publicLocation,
  };

  @override
  bool operator ==(Object other) =>
      other is EmergencyAssemblyPoint &&
      other.label == label &&
      other.publicLocation == publicLocation;

  @override
  int get hashCode => Object.hash(label, publicLocation);
}

final class OfficialReportChannel {
  const OfficialReportChannel({
    required this.label,
    required this.url,
    required this.phone,
  });

  final String label;
  final String? url;
  final String? phone;

  /// Only these validated URIs may be handed to the operating system.
  Uri? get safeUrlUri => _safeHttpsUri(url);
  Uri? get safePhoneUri => _safePhoneUri(phone);

  factory OfficialReportChannel.fromWire(Object? raw) {
    final wire = _wireMap(raw, 'official report channel');
    _expectKeys(wire, const {'label'}, const {'url', 'phone'});
    final label = _cleanText(wire['label'], 'official channel label', 80);
    final hasUrl = wire.containsKey('url');
    final hasPhone = wire.containsKey('phone');
    if (!hasUrl && !hasPhone) {
      throw const FormatException('An official channel needs a URL or phone.');
    }
    final url = hasUrl ? _cleanText(wire['url'], 'channel url', 2048) : null;
    final phone = hasPhone ? _validPhone(wire['phone'], 'channel phone') : null;
    if (url != null && _safeHttpsUri(url) == null) {
      throw const FormatException('An official channel URL must use HTTPS.');
    }
    return OfficialReportChannel(label: label, url: url, phone: phone);
  }

  Map<String, Object?> toWire() => {
    'label': label,
    if (url != null) 'url': url,
    if (phone != null) 'phone': phone,
  };

  @override
  bool operator ==(Object other) =>
      other is OfficialReportChannel &&
      other.label == label &&
      other.url == url &&
      other.phone == phone;

  @override
  int get hashCode => Object.hash(label, url, phone);
}

Map<String, Object?> _wireMap(Object? value, String name) {
  if (value is! Map) throw FormatException('Invalid $name.');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw FormatException('Invalid $name.');
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _expectKeys(
  Map<String, Object?> wire,
  Set<String> required,
  Set<String> optional,
) {
  if (!wire.keys.toSet().containsAll(required) ||
      wire.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('Emergency directory fields are invalid.');
  }
}

List<Object?> _requiredList(Object? value, String name) {
  if (value is! List) throw FormatException('Invalid $name.');
  return List<Object?>.from(value);
}

String _requiredText(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $name.');
  }
  return value.trim();
}

int _positiveVersion(Object? value) {
  if (value is! int || value <= 0 || value > 9007199254740991) {
    throw const FormatException('Invalid emergency directory version.');
  }
  return value;
}

DateTime _requiredDate(Object? value, String name, DateTime now) {
  final date = value is DateTime
      ? value
      : value is String
      ? DateTime.tryParse(value)
      : null;
  if (date == null || date.isAfter(now)) {
    throw FormatException('Invalid $name.');
  }
  return date.toUtc();
}

List<EmergencyContact> _contacts(Object? value) {
  final items = _requiredList(value, 'emergencyContacts');
  if (items.isEmpty || items.length > 10) {
    throw const FormatException('Invalid emergencyContacts count.');
  }
  return List<EmergencyContact>.unmodifiable(
    items.map(EmergencyContact.fromWire),
  );
}

List<EmergencyAssemblyPoint> _assemblyPoints(Object? value) {
  final items = _requiredList(value, 'assemblyPoints');
  if (items.isEmpty || items.length > 10) {
    throw const FormatException('Invalid assemblyPoints count.');
  }
  return List<EmergencyAssemblyPoint>.unmodifiable(
    items.map(EmergencyAssemblyPoint.fromWire),
  );
}

List<OfficialReportChannel> _reportChannels(Object? value) {
  final items = _requiredList(value, 'officialReportChannels');
  if (items.length > 10) {
    throw const FormatException('Invalid officialReportChannels count.');
  }
  return List<OfficialReportChannel>.unmodifiable(
    items.map(OfficialReportChannel.fromWire),
  );
}

String _cleanText(Object? value, String name, int maxLength) {
  final text = _requiredText(value, name);
  if (text.runes.length > maxLength ||
      RegExp(r'[\x00-\x1F\x7F]').hasMatch(text)) {
    throw FormatException('Invalid $name.');
  }
  return text;
}

String _validPhone(Object? value, String name) {
  final phone = _cleanText(value, name, 32);
  if (!RegExp(r'^\+?[0-9][0-9 ()./-]*$').hasMatch(phone)) {
    throw FormatException('Invalid $name.');
  }
  final digitCount = phone.replaceAll(RegExp(r'\D'), '').length;
  if (digitCount < 3 || digitCount > 15) {
    throw FormatException('Invalid $name.');
  }
  return phone;
}

Uri? _safeHttpsUri(String? value) {
  if (value == null ||
      value.isEmpty ||
      value != value.trim() ||
      RegExp(r'[\x00-\x20\x7F]').hasMatch(value)) {
    return null;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  return uri;
}

Uri? _safePhoneUri(String? value) {
  if (value == null || !RegExp(r'^\+?[0-9][0-9 ()./-]*$').hasMatch(value)) {
    return null;
  }
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 3 || digits.length > 15) return null;
  final dialString = '${value.startsWith('+') ? '+' : ''}$digits';
  return Uri(scheme: 'tel', path: dialString);
}

bool _sameList<T>(List<T> first, List<T> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}
