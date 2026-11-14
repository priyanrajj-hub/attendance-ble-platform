import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// Hardware-backed biometric service for user presence verification.
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

  /// Lists available biometric sensors enrolled on this device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Prompts the user to verify physical presence via biometrics before check-in.
  Future<BiometricResult> verifyAttendanceBiometric() async {
    return authenticate(
      reason: 'Scan your biometric credential to confirm physical presence for class attendance.',
      biometricOnly: true,
    );
  }

  /// Core biometric prompt method.
  /// Strictly requires biometricOnly: true (no PIN/pattern fallback).
  Future<BiometricResult> authenticate({
    required String reason,
    bool biometricOnly = true,
  }) async {
    try {
      final supported = await isBiometricSupported();
      if (!supported) {
        return const BiometricResult.failure(
          'No biometric hardware or enrolled biometrics found on this device. Please enroll a biometric credential in your device settings.',
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
          'Biometric verification was cancelled or did not match.',
        );
      }
    } on PlatformException catch (e) {
      return BiometricResult.failure('Biometric authentication error: ${e.message ?? e.code}');
    } catch (e) {
      return BiometricResult.failure('Authentication failed: $e');
    }
  }
}

class BiometricResult {
  final bool isSuccess;
  final String? errorMessage;

  const BiometricResult.success()
      : isSuccess = true,
        errorMessage = null;

  const BiometricResult.failure(this.errorMessage)
      : isSuccess = false;
}

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});
