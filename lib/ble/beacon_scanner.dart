class BeaconSighting {
  final String code;
  final int rssi;
  final DateTime seenAt;

  const BeaconSighting({
    required this.code,
    required this.rssi,
    required this.seenAt,
  });

  @override
  String toString() => 'BeaconSighting(code: $code, rssi: $rssi dBm, seenAt: $seenAt)';
}

abstract class BeaconScanner {
  /// Watches for incoming advertisements matching the app namespace.
  Stream<BeaconSighting> watch();

  /// Stops active BLE scanning.
  Future<void> stop();
}
