sealed class BleFailure {
  final String message;
  const BleFailure(this.message);
}

final class PermissionDeniedFailure extends BleFailure {
  const PermissionDeniedFailure([super.message = 'Bluetooth or location permission was denied.']);
}

final class PermanentlyDeniedFailure extends BleFailure {
  const PermanentlyDeniedFailure([super.message = 'Bluetooth permissions permanently denied. Please enable in App Settings.']);
}

final class AdapterOffFailure extends BleFailure {
  const AdapterOffFailure([super.message = 'Bluetooth adapter is turned off. Please turn Bluetooth ON.']);
}

final class UnsupportedFailure extends BleFailure {
  const UnsupportedFailure([super.message = 'BLE operations are not supported on this device.']);
}

final class NoBeaconFoundFailure extends BleFailure {
  const NoBeaconFoundFailure([super.message = 'No faculty beacon detected within physical proximity.']);
}

final class WeakSignalFailure extends BleFailure {
  final int rssi;
  final int threshold;
  const WeakSignalFailure(this.rssi, this.threshold)
      : super('Signal too weak ($rssi dBm < $threshold dBm). Please move closer to the front desk.');
}

final class CodeRejectedFailure extends BleFailure {
  const CodeRejectedFailure([super.message = 'Beacon rotation code expired or was rejected by classroom security rules.']);
}

final class NotEnrolledFailure extends BleFailure {
  const NotEnrolledFailure([super.message = 'You are not enrolled in this course session. Contact faculty.']);
}

final class DeviceNotBoundFailure extends BleFailure {
  const DeviceNotBoundFailure([super.message = 'Device binding mismatch. Attendance must be marked from your registered device.']);
}

final class SessionClosedFailure extends BleFailure {
  const SessionClosedFailure([super.message = 'The attendance session for this class is closed or has expired.']);
}

final class BiometricFailedFailure extends BleFailure {
  const BiometricFailedFailure([super.message = 'Biometric presence verification was cancelled or did not match.']);
}

final class UnknownBleFailure extends BleFailure {
  const UnknownBleFailure(super.message);
}
