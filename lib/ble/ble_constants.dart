class BleConstants {
  /// 12-byte fixed app namespace: "AMRTBLE" padded with zeros: 41 4D 52 54 42 4C 45 00 00 00 00 00
  static const String namespaceHex = '414d5254424c450000000000';

  /// Standard default RSSI threshold for indoor physical classroom proximity.
  static const int defaultMinRssi = -80;

  /// Beacon rotation period in seconds.
  static const int rotationPeriodSeconds = 20;

  /// Maximum scan duration in seconds before timing out.
  static const int scanTimeoutSeconds = 10;

  /// Minimum consecutive sightings required within window.
  static const int requiredSightings = 2;

  /// Window in seconds within which required sightings must occur.
  static const int sightingWindowSeconds = 6;

  /// Assembles a standard 128-bit UUID (8-4-4-4-12 format) from namespace + 8-hex rotating code.
  static String buildBeaconUuid(String code8Hex) {
    final cleanCode = code8Hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    if (cleanCode.length != 8) {
      throw ArgumentError('Rotating code must be exactly 8 hex characters: $code8Hex');
    }
    // 414d5254-424c-4500-0000-0000 + 8-char code
    return '414d5254-424c-4500-0000-0000$cleanCode';
  }

  /// Builds a standard 128-bit RFC4122 UUID from a 32-hex cryptographic challenge.
  static String buildChallengeUuid(String challenge32Hex) {
    final clean = challenge32Hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    if (clean.length != 32) {
      throw ArgumentError('128-bit challenge must be exactly 32 hex characters: $challenge32Hex');
    }
    return '${clean.substring(0, 8)}-${clean.substring(8, 12)}-${clean.substring(12, 16)}-${clean.substring(16, 20)}-${clean.substring(20, 32)}';
  }

  /// Extracts the 8-hex code from an advertisement UUID if it matches the app namespace.
  static String? extractCode(String uuidString) {
    final clean = uuidString.replaceAll('-', '').toLowerCase();
    if (clean.length == 32 && clean.startsWith(namespaceHex)) {
      return clean.substring(24, 32);
    }
    return null;
  }

  /// Extracts the challenge from a UUID string, rejecting foreign Bluetooth SIG standard UUIDs
  /// and extracting either 128-bit challenges or app-namespaced codes.
  static String? extractChallenge(String uuidString) {
    final clean = uuidString.replaceAll('-', '').toLowerCase();
    if (clean.length == 32) {
      // Reject Bluetooth SIG standard base UUIDs (0000xxxx-0000-1000-8000-00805f9b34fb)
      if (clean.contains('00001000800000805f9b34fb')) {
        return null;
      }
      if (clean.startsWith(namespaceHex)) {
        return clean.substring(24, 32);
      }
      return clean;
    }
    return null;
  }
}
