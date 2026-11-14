import 'dart:async';
import 'ble_failure.dart';

abstract class BeaconBroadcaster {
  /// Starts broadcasting the specified 128-bit service UUID without device name.
  Future<void> start(String uuid);

  /// Stops BLE broadcasting.
  Future<void> stop();

  /// Stream of broadcaster failures or unexpected radio interruptions.
  Stream<BleFailure> get failures;

  /// True if currently advertising.
  bool get isAdvertising;
}
