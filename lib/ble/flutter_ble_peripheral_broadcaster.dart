import 'dart:async';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'beacon_broadcaster.dart';
import 'ble_failure.dart';

class FlutterBlePeripheralBroadcaster implements BeaconBroadcaster {
  final FlutterBlePeripheral _peripheral;
  final _failureController = StreamController<BleFailure>.broadcast();
  bool _isAdvertising = false;

  FlutterBlePeripheralBroadcaster({FlutterBlePeripheral? peripheral})
      : _peripheral = peripheral ?? FlutterBlePeripheral();

  @override
  Stream<BleFailure> get failures => _failureController.stream;

  @override
  bool get isAdvertising => _isAdvertising;

  @override
  Future<void> start(String uuid) async {
    try {
      final isSupported = await _peripheral.isSupported;
      if (!isSupported) {
        final err = const UnsupportedFailure();
        _failureController.add(err);
        throw err;
      }

      // Stop previous advertisement before re-starting with new UUID
      if (_isAdvertising) {
        await _peripheral.stop();
      }

      final advertiseData = AdvertiseData(
        serviceUuid: uuid,
        includeDeviceName: false,
      );

      await _peripheral.start(advertiseData: advertiseData);
      _isAdvertising = true;
    } catch (e) {
      _isAdvertising = false;
      final failure = UnknownBleFailure('Broadcasting failed: $e');
      _failureController.add(failure);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      if (_isAdvertising) {
        await _peripheral.stop();
        _isAdvertising = false;
      }
    } catch (e) {
      _failureController.add(UnknownBleFailure('Failed to stop broadcast: $e'));
    }
  }

  void dispose() {
    _failureController.close();
  }
}
