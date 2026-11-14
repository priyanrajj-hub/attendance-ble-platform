import 'dart:convert';
import 'package:crypto/crypto.dart';

class ChallengeCrypto {
  /// Standard rotation period in seconds.
  static const int rotationPeriodSeconds = 20;

  /// Derives a 128-bit (32 hex characters) cryptographic challenge bound to a specific session and time step.
  /// Uses HMAC-SHA256 over '$sessionId:$step'.
  static String computeChallenge({
    required String sessionSecret,
    required String sessionId,
    required int step,
  }) {
    final keyBytes = utf8.encode(sessionSecret);
    final messageBytes = utf8.encode('$sessionId:$step');
    final hmac = Hmac(sha256, keyBytes);
    final digest = hmac.convert(messageBytes);
    // Take first 16 bytes (128 bits = 32 hex chars)
    return digest.toString().substring(0, 32);
  }

  /// Calculates the current time step for a given UTC timestamp.
  static int currentStep([DateTime? refTime]) {
    final now = refTime ?? DateTime.now().toUtc();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    return epochSeconds ~/ rotationPeriodSeconds;
  }

  /// Formats a 32-hex-character challenge string into a valid RFC4122 128-bit UUID format (8-4-4-4-12).
  static String formatAsUuid(String challenge32Hex) {
    final clean = challenge32Hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    if (clean.length != 32) {
      throw ArgumentError('Challenge must be exactly 32 hex characters (128 bits): $challenge32Hex');
    }
    return '${clean.substring(0, 8)}-${clean.substring(8, 12)}-${clean.substring(12, 16)}-${clean.substring(16, 20)}-${clean.substring(20, 32)}';
  }

  /// Extracts the clean 32-hex challenge from a 128-bit UUID string.
  static String extractChallengeFromUuid(String uuidString) {
    return uuidString.replaceAll('-', '').toLowerCase();
  }
}
