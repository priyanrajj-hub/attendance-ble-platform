import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'beacon_scanner.dart';
import 'ble_constants.dart';

class FlutterBluePlusScanner implements BeaconScanner {
  StreamSubscription<List<ScanResult>>? _subscription;
  final _sightingController = StreamController<BeaconSighting>.broadcast();

  @override
  Stream<BeaconSighting> watch() {
    _startScan();
    return _sightingController.stream;
  }

  Future<void> _startScan() async {
    await stop();

    _subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        for (final guid in result.advertisementData.serviceUuids) {
          final code = BleConstants.extractChallenge(guid.toString());
          if (code != null) {
            _sightingController.add(BeaconSighting(
              code: code,
              rssi: result.rssi,
              seenAt: result.timeStamp,
            ));
          }
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
      );
    } catch (e) {
      if (!_sightingController.isClosed) {
        _sightingController.addError(e);
      }
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _subscription?.cancel();
      _subscription = null;
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}
  }

  void dispose() {
    stop();
    _sightingController.close();
  }
}
