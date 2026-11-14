import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'beacon_broadcaster.dart';
import 'ble_constants.dart';

enum BeaconHealth {
  idle,
  advertising,
  unhealthy,
  stopped,
}

class CodeRotator {
  final String sessionId;
  final BeaconBroadcaster _broadcaster;
  final FirebaseFirestore _firestore;

  Timer? _rotationTimer;
  String? _currentCode;
  String? _prevCode;
  BeaconHealth _health = BeaconHealth.idle;
  String? _lastError;

  final _healthController = StreamController<BeaconHealth>.broadcast();

  CodeRotator({
    required this.sessionId,
    required BeaconBroadcaster broadcaster,
    FirebaseFirestore? firestore,
  })  : _broadcaster = broadcaster,
        _firestore = firestore ?? FirebaseFirestore.instance {
    _healthController.add(_health);
  }

  BeaconHealth get health => _health;
  String? get currentCode => _currentCode;
  String? get lastError => _lastError;
  Stream<BeaconHealth> get healthStream => _healthController.stream;

  static String generate8HexCode() {
    final random = Random.secure();
    final bytes = List<int>.generate(4, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _setHealth(BeaconHealth newHealth, {String? error}) {
    _health = newHealth;
    _lastError = error;
    if (!_healthController.isClosed) {
      _healthController.add(_health);
    }
  }

  Future<void> start() async {
    try {
      // Keep faculty screen awake during active broadcast session
      await WakelockPlus.enable();
    } catch (_) {}

    await _rotateAndAdvertise();

    _rotationTimer?.cancel();
    _rotationTimer = Timer.periodic(
      const Duration(seconds: BleConstants.rotationPeriodSeconds),
      (_) => _rotateAndAdvertise(),
    );
  }

  Future<void> _rotateAndAdvertise() async {
    try {
      _prevCode = _currentCode;
      _currentCode = generate8HexCode();

      // 1. Write rotated code to Firestore
      final liveRef = _firestore
          .collection('sessions')
          .doc(sessionId)
          .collection('live')
          .doc('current');

      final data = <String, dynamic>{
        'code': _currentCode,
        'rotatedAt': FieldValue.serverTimestamp(),
      };
      if (_prevCode != null) {
        data['prevCode'] = _prevCode;
      }

      await liveRef.set(data);

      // 2. Restart advertising with new 128-bit UUID
      final uuid = BleConstants.buildBeaconUuid(_currentCode!);
      await _broadcaster.start(uuid);

      _setHealth(BeaconHealth.advertising);
    } catch (e) {
      debugPrint('Code rotation failure: $e');
      _setHealth(BeaconHealth.unhealthy, error: e.toString());
    }
  }

  Future<void> stop() async {
    _rotationTimer?.cancel();
    _rotationTimer = null;
    try {
      await _broadcaster.stop();
      await WakelockPlus.disable();
    } catch (_) {}
    _setHealth(BeaconHealth.stopped);
  }

  void dispose() {
    stop();
    _healthController.close();
  }
}
