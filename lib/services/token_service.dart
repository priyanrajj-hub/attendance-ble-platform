import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// HMAC-based rotating token service for BLE attendance verification.
///
/// Produces 30-second-bucket tokens using HMAC-SHA256 over
/// `sessionId + timeBucket`. The faculty scanner sends scanned tokens
/// to the backend, which re-derives the expected HMAC and compares.
///
/// This prevents replay attacks — a token captured in one 30-second
/// window is invalid in the next.
class TokenService {
  /// Generate a cryptographically random secret for a new session.
  static String generateSessionSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// Compute the current time bucket (30-second intervals since epoch).
  static int currentTimeBucket() {
    return DateTime.now().millisecondsSinceEpoch ~/ 30000;
  }

  /// Generate the rotating HMAC token for the current 30-second window.
  ///
  /// Both the student app and the verification backend call this with
  /// the same [sessionId] + [secret] + time bucket to produce/verify.
  ///
  /// SECURITY NOTE: The HMAC-SHA256 signature is intentionally truncated
  /// to 8 hex characters (32 bits) to accommodate strict BLE payload budgets.
  /// While sufficient when guarded by physical proximity heuristics (RSSI),
  /// 32 bits represents a relatively small brute-force search space if the
  /// proximity constraint is loosened or bypassed.
  static String generateToken(String sessionId, String secret) {
    final bucket = currentTimeBucket();
    final message = '$sessionId:$bucket';
    final key = utf8.encode(secret);
    final hmacResult = Hmac(sha256, key).convert(utf8.encode(message));
    // Return first 8 bytes (16 hex chars) — fits in BLE manufacturer data
    return hmacResult.toString().substring(0, 16);
  }

  /// Verify a received token against the expected HMAC.
  ///
  /// Checks both the current bucket AND the previous bucket (±30s tolerance)
  /// to account for clock drift between student and faculty devices.
  static bool verifyToken(
      String sessionId, String secret, String receivedToken) {
    final currentBucket = currentTimeBucket();

    for (int offset = -1; offset <= 1; offset++) {
      final bucket = currentBucket + offset;
      final message = '$sessionId:$bucket';
      final key = utf8.encode(secret);
      final hmacResult = Hmac(sha256, key).convert(utf8.encode(message));
      final expected = hmacResult.toString().substring(0, 16);

      if (expected == receivedToken) return true;
    }
    return false;
  }

  /// Verify a received token fragment (8 chars) against the expected HMAC.
  ///
  /// Checks the current, previous, and next buckets (±30s tolerance)
  /// to account for clock drift between student and faculty devices.
  static bool verifyTokenFragment(
      String sessionId, String secret, String receivedFragment) {
    final currentBucket = currentTimeBucket();

    for (int offset = -1; offset <= 1; offset++) {
      final bucket = currentBucket + offset;
      final message = '$sessionId:$bucket';
      final key = utf8.encode(secret);
      final hmacResult = Hmac(sha256, key).convert(utf8.encode(message));
      final expectedFragment = hmacResult.toString().substring(0, 8);

      if (expectedFragment == receivedFragment) return true;
    }
    return false;
  }

  /// Encode student UID + HMAC token into BLE manufacturer data bytes.
  ///
  /// Format: [studentUid (first 8 chars, 8 bytes) | hmacToken (8 bytes)]
  /// Total: 16 bytes — fits within BLE advertisement limits.
  static List<int> encodeBlePayload(String studentUid, String hmacToken) {
    final uidBytes = utf8.encode(
        studentUid.substring(0, studentUid.length > 8 ? 8 : studentUid.length));
    // Pad UID to exactly 8 bytes
    final paddedUid = List<int>.filled(8, 0)
      ..setRange(0, uidBytes.length, uidBytes);
    final tokenBytes = utf8.encode(hmacToken.substring(0, 8));
    return [...paddedUid, ...tokenBytes];
  }

  /// Decode BLE manufacturer data back into student UID prefix + HMAC token.
  static ({String uidPrefix, String tokenFragment})? decodeBlePayload(
      List<int> bytes) {
    if (bytes.length < 16) return null;
    try {
      final uidPrefix = utf8.decode(bytes.sublist(0, 8)).replaceAll('\x00', '');
      final tokenFragment = utf8.decode(bytes.sublist(8, 16));
      return (uidPrefix: uidPrefix, tokenFragment: tokenFragment);
    } catch (_) {
      return null;
    }
  }
}
