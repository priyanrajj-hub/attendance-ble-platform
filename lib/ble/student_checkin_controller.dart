import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/biometric_service.dart';
import 'beacon_scanner.dart';
import 'ble_constants.dart';
import 'ble_failure.dart';
import 'device_binding_service.dart';
import 'flutter_blue_plus_scanner.dart';

sealed class CheckInState {
  const CheckInState();
}

final class CheckInIdle extends CheckInState {
  const CheckInIdle();
}

final class CheckInBiometricsPending extends CheckInState {
  const CheckInBiometricsPending();
}

final class CheckInScanning extends CheckInState {
  final int sightingsCount;
  const CheckInScanning({this.sightingsCount = 0});
}

final class CheckInSubmitting extends CheckInState {
  final String code;
  final int rssi;
  const CheckInSubmitting({required this.code, required this.rssi});
}

final class CheckInSuccess extends CheckInState {
  final String sessionId;
  final DateTime serverTime;
  final int rssi;
  const CheckInSuccess({
    required this.sessionId,
    required this.serverTime,
    required this.rssi,
  });
}

final class CheckInError extends CheckInState {
  final BleFailure failure;
  const CheckInError(this.failure);
}

class StudentCheckInController extends StateNotifier<CheckInState> {
  final BiometricService _biometricService;
  final DeviceBindingService _deviceBindingService;
  final BeaconScanner _scanner;
  final FirebaseFirestore _firestore;

  StudentCheckInController({
    required BiometricService biometricService,
    required DeviceBindingService deviceBindingService,
    required BeaconScanner scanner,
    FirebaseFirestore? firestore,
  })  : _biometricService = biometricService,
        _deviceBindingService = deviceBindingService,
        _scanner = scanner,
        _firestore = firestore ?? FirebaseFirestore.instance,
        super(const CheckInIdle());

  Future<void> executeCheckIn({
    required String sessionId,
    required String studentUid,
    required String? remoteDeviceId,
    int minRssi = BleConstants.defaultMinRssi,
  }) async {
    // 1. Mandatory Biometric Check First (so rotating nonce cannot expire during prompt)
    state = const CheckInBiometricsPending();
    final bioResult = await _biometricService.verifyAttendanceBiometric();
    if (!bioResult.isSuccess) {
      state = CheckInError(BiometricFailedFailure(
        bioResult.errorMessage ?? 'Biometric verification required to confirm physical presence.',
      ));
      return;
    }

    // 2. Device Binding Pre-check
    final isBound = await _deviceBindingService.ensureDeviceBound(studentUid, remoteDeviceId);
    if (!isBound) {
      state = const CheckInError(DeviceNotBoundFailure());
      return;
    }
    final localDeviceId = await _deviceBindingService.getOrCreateDeviceId();

    // 3. Permissions & Bluetooth Adapter State
    final permFailure = await _checkPermissionsAndAdapter();
    if (permFailure != null) {
      state = CheckInError(permFailure);
      return;
    }

    // 4. Scan up to 10 seconds for beacon sightings
    state = const CheckInScanning();
    final sightingsByCode = <String, List<BeaconSighting>>{};
    final completer = Completer<BeaconSighting?>();
    StreamSubscription<BeaconSighting>? sub;
    Timer? timeoutTimer;

    sub = _scanner.watch().listen((sighting) {
      final list = sightingsByCode.putIfAbsent(sighting.code, () => []);
      list.add(sighting);

      if (mounted) {
        state = CheckInScanning(sightingsCount: list.length);
      }

      // Check window condition: >= 2 sightings of the same code within 6 seconds
      final now = DateTime.now();
      final recentSightings = list.where(
        (s) => now.difference(s.seenAt).inSeconds <= BleConstants.sightingWindowSeconds,
      ).toList();

      if (recentSightings.length >= BleConstants.requiredSightings) {
        if (!completer.isCompleted) {
          completer.complete(recentSightings.last);
        }
      }
    });

    timeoutTimer = Timer(const Duration(seconds: BleConstants.scanTimeoutSeconds), () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    final winner = await completer.future;
    await sub.cancel();
    timeoutTimer.cancel();
    await _scanner.stop();

    if (winner == null) {
      state = const CheckInError(NoBeaconFoundFailure());
      return;
    }

    // 5. Evaluate RSSI threshold gate
    final codeSightings = sightingsByCode[winner.code] ?? [winner];
    final meanRssi = codeSightings.map((s) => s.rssi).reduce((a, b) => a + b) / codeSightings.length;

    if (meanRssi < minRssi) {
      state = CheckInError(WeakSignalFailure(meanRssi.round(), minRssi));
      return;
    }

    // 6. Write Attendance Record Immediately
    state = CheckInSubmitting(code: winner.code, rssi: meanRssi.round());
    try {
      final recordRef = _firestore
          .collection('sessions')
          .doc(sessionId)
          .collection('attendance')
          .doc(studentUid);

      await recordRef.set({
        'studentUid': studentUid,
        'markedAt': FieldValue.serverTimestamp(),
        'method': 'ble',
        'code': winner.code,
        'rssi': meanRssi.round(),
        'deviceId': localDeviceId,
      });

      state = CheckInSuccess(
        sessionId: sessionId,
        serverTime: DateTime.now(),
        rssi: meanRssi.round(),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        state = const CheckInError(CodeRejectedFailure());
      } else {
        state = CheckInError(UnknownBleFailure(e.message ?? e.code));
      }
    } catch (e) {
      state = CheckInError(UnknownBleFailure('Check-in write failed: $e'));
    }
  }

  Future<BleFailure?> _checkPermissionsAndAdapter() async {
    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        return const AdapterOffFailure();
      }
    } catch (_) {}

    try {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
        return const PermanentlyDeniedFailure();
      }
      if (!scanStatus.isGranted || !connectStatus.isGranted) {
        final locStatus = await Permission.locationWhenInUse.request();
        if (!locStatus.isGranted) {
          return const PermissionDeniedFailure();
        }
      }
    } catch (_) {}

    return null;
  }
}

final studentCheckInControllerProvider =
    StateNotifierProvider<StudentCheckInController, CheckInState>((ref) {
  return StudentCheckInController(
    biometricService: ref.watch(biometricServiceProvider),
    deviceBindingService: ref.watch(deviceBindingServiceProvider),
    scanner: FlutterBluePlusScanner(),
    firestore: FirebaseFirestore.instance,
  );
});
