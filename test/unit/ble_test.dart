import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/ble/beacon_broadcaster.dart';
import 'package:amrita_ble_attendance/ble/beacon_scanner.dart';
import 'package:amrita_ble_attendance/ble/ble_constants.dart';
import 'package:amrita_ble_attendance/ble/ble_failure.dart';
import 'package:amrita_ble_attendance/ble/code_rotator.dart';
import 'package:amrita_ble_attendance/ble/device_binding_service.dart';

class _FakeBeaconBroadcaster implements BeaconBroadcaster {
  String? lastAdvertisedUuid;
  bool _advertising = false;
  final _failureController = StreamController<BleFailure>.broadcast();

  @override
  Stream<BleFailure> get failures => _failureController.stream;

  @override
  bool get isAdvertising => _advertising;

  @override
  Future<void> start(String uuid) async {
    lastAdvertisedUuid = uuid;
    _advertising = true;
  }

  @override
  Future<void> stop() async {
    _advertising = false;
  }

  void dispose() {
    _failureController.close();
  }
}

class _FakeBeaconScanner implements BeaconScanner {
  final _controller = StreamController<BeaconSighting>.broadcast();

  void emitSighting(BeaconSighting sighting) {
    _controller.add(sighting);
  }

  @override
  Stream<BeaconSighting> watch() => _controller.stream;

  @override
  Future<void> stop() async {}

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('Phase 4: Real BLE Layer Unit Tests', () {
    test('UUID encode/decode round trip with app namespace', () {
      const code = 'a1b2c3d4';
      final uuid = BleConstants.buildBeaconUuid(code);

      // Verify format
      expect(uuid, '414d5254-424c-4500-0000-0000a1b2c3d4');

      // Verify extraction
      final extracted = BleConstants.extractCode(uuid);
      expect(extracted, code);
    });

    test('UUID extraction rejects foreign non-app UUIDs', () {
      const foreignUuid = '0000180d-0000-1000-8000-00805f9b34fb';
      final extracted = BleConstants.extractCode(foreignUuid);
      expect(extracted, isNull);

      final challenge = BleConstants.extractChallenge(foreignUuid);
      expect(challenge, isNull);
    });

    test('generate8HexCode produces unique 8-character hex strings', () {
      final code1 = CodeRotator.generate8HexCode();
      final code2 = CodeRotator.generate8HexCode();

      expect(code1.length, 8);
      expect(code2.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(code1), isTrue);
      expect(code1, isNot(code2));
    });

    test('generateUuidV4 produces valid RFC4122 v4 UUIDs', () {
      final uuid1 = DeviceBindingService.generateUuidV4();
      final uuid2 = DeviceBindingService.generateUuidV4();

      expect(uuid1, isNot(uuid2));
      // Version 4 is in position 14 (0-indexed: 8-4-[4]-4-12)
      expect(uuid1[14], '4');
      // Variant 8, 9, a, or b in position 19
      expect(['8', '9', 'a', 'b'].contains(uuid1[19].toLowerCase()), isTrue);
    });

    test('BleFailure mapping contains all required failure types', () {
      const List<BleFailure> failures = [
        PermissionDeniedFailure(),
        PermanentlyDeniedFailure(),
        AdapterOffFailure(),
        UnsupportedFailure(),
        NoBeaconFoundFailure(),
        WeakSignalFailure(-85, -80),
        CodeRejectedFailure(),
        NotEnrolledFailure(),
        DeviceNotBoundFailure(),
        SessionClosedFailure(),
        BiometricFailedFailure(),
        UnknownBleFailure('Test error'),
      ];

      for (final f in failures) {
        expect(f.message, isNotEmpty);
      }
    });

    test('Fake broadcaster and scanner contracts', () async {
      final broadcaster = _FakeBeaconBroadcaster();
      final scanner = _FakeBeaconScanner();

      await broadcaster.start('414d5254-424c-4500-0000-000012345678');
      expect(broadcaster.isAdvertising, isTrue);
      expect(broadcaster.lastAdvertisedUuid, contains('12345678'));

      await broadcaster.stop();
      expect(broadcaster.isAdvertising, isFalse);

      final nextSighting = scanner.watch().first;
      scanner.emitSighting(BeaconSighting(code: '12345678', rssi: -65, seenAt: DateTime.now()));
      final seen = await nextSighting;
      expect(seen.code, '12345678');
      expect(seen.rssi, -65);

      broadcaster.dispose();
      scanner.dispose();
    });

    test('CodeRotator enforces non-empty sessionId and sessionSecret', () {
      final broadcaster = _FakeBeaconBroadcaster();
      expect(
        () => CodeRotator(
          sessionId: '',
          sessionSecret: 'secret_123',
          broadcaster: broadcaster,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CodeRotator(
          sessionId: 'session_123',
          sessionSecret: '',
          broadcaster: broadcaster,
        ),
        throwsA(isA<AssertionError>()),
      );
      broadcaster.dispose();
    });
  });
}
