import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/services/biometric_service.dart';

void main() {
  group('BiometricService Hardware Enforcement Tests', () {
    test('Without hardware/enrolled sensors, returns failure rather than simulated success', () async {
      final bioService = BiometricService();
      final result = await bioService.verifyAttendanceBiometric();

      // In unit test / headless environment without hardware, fails safely without fake pass
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('No biometric hardware or enrolled biometrics'));
    });
  });
}
