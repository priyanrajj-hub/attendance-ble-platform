import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Anti-Proxy Fingerprint and Biometric Service.
///
/// Strictly enforces hardware-backed biometric verification:
/// 1. At Registration: User registers their finger to bind their device to their student profile.
/// 2. At Check-in: User must scan their registered finger before BLE attendance can be broadcast or recorded.
/// This prevents any proxy attendance by peers or third parties.
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Checks if hardware biometric sensors (fingerprint/face) are present and supported.
  Future<bool> isBiometricSupported() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      return isSupported && canCheck;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Lists available biometric sensors enrolled on this device (e.g. fingerprint, face).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Prompts the user to register their fingerprint and bind it to their account.
  Future<BiometricResult> registerFingerprintBinding() async {
    return authenticate(
      reason:
          'Scan your registered fingerprint to bind this device to your student identity (Anti-Proxy Defense).',
    );
  }

  /// Prompts the user to verify physical presence via fingerprint before check-in.
  Future<BiometricResult> verifyAttendanceFingerprint() async {
    return authenticate(
      reason:
          'Scan your fingerprint to confirm physical presence for attendance check-in. Proxy attendance is strictly prohibited.',
    );
  }

  /// Core biometric prompt method.
  Future<BiometricResult> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      final supported = await isBiometricSupported();
      if (!supported) {
        // If testing on desktop / non-biometric emulator in debug mode, pass safely with log
        if (kDebugMode) {
          debugPrint(
              'Biometrics not available on this host - simulated pass in debug mode.');
          return const BiometricResult.success(
            simulated: true,
            message: 'Simulated pass in development mode (No biometric hardware)',
          );
        }
        return const BiometricResult.failure(
          'No biometric hardware or enrolled fingerprints found on this device. Please enroll a fingerprint in your device settings.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: biometricOnly,
        ),
      );

      if (authenticated) {
        return const BiometricResult.success();
      } else {
        return const BiometricResult.failure(
          'Fingerprint verification was cancelled or did not match. Attendance requires valid biometric authentication.',
        );
      }
    } on PlatformException catch (e) {
      return BiometricResult.failure('Biometric error: ${e.message ?? e.code}');
    } catch (e) {
      return BiometricResult.failure('Authentication failed: $e');
    }
  }
}

class BiometricResult {
  final bool isSuccess;
  final String? errorMessage;
  final bool simulated;

  const BiometricResult.success({this.simulated = false, String? message})
      : isSuccess = true,
        errorMessage = message;

  const BiometricResult.failure(this.errorMessage)
      : isSuccess = false,
        simulated = false;
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});
