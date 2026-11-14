import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/biometric_service.dart';
import '../services/attendance_api_service.dart';
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
  final AttendanceApiService? _apiService;

  StudentCheckInController({
    required BiometricService biometricService,
    required DeviceBindingService deviceBindingService,
    required BeaconScanner scanner,
    AttendanceApiService? apiService,
  })  : _biometricService = biometricService,
        _deviceBindingService = deviceBindingService,
        _scanner = scanner,
        _apiService = apiService,
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
    }, onError: (_) {
      if (!completer.isCompleted) {
        completer.complete(null);
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

    // 5. Evaluate RSSI threshold gate (using strictly fresh window sightings)
    final now = DateTime.now();
    final freshSightings = (sightingsByCode[winner.code] ?? [winner])
        .where((s) => now.difference(s.seenAt).inSeconds <= BleConstants.sightingWindowSeconds)
        .toList();
    final effectiveSightings = freshSightings.isNotEmpty ? freshSightings : [winner];
    final meanRssi = effectiveSightings.map((s) => s.rssi).reduce((a, b) => a + b) / effectiveSightings.length;

    if (meanRssi < minRssi) {
      state = CheckInError(WeakSignalFailure(meanRssi.round(), minRssi));
      return;
    }

    // 6. Generate Cryptographic Device Signature and Submit to PostgreSQL Authority via FastAPI
    state = CheckInSubmitting(code: winner.code, rssi: meanRssi.round());

    if (_apiService == null) {
      state = const CheckInError(UnknownBleFailure('Authoritative attendance service is unconfigured.'));
      return;
    }

    try {
      // Ensure hardware device public key is registered with backend
      final pem = await _deviceBindingService.getPublicKeyPem();
      await _apiService.registerDevice(
        publicKeyPem: pem,
        platform: 'android',
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final signature = await _deviceBindingService.signPayload(
        sessionId: sessionId,
        nonce: winner.code,
        timestamp: timestamp,
      );
      final fingerprint = await _deviceBindingService.getPublicKeyFingerprint();

      final apiRes = await _apiService.submitProximityCheckIn(
        sessionId: sessionId,
        ephemeralNonce: winner.code,
        observedRssi: meanRssi.round(),
        clientTimestamp: timestamp,
        publicKeyFingerprint: fingerprint,
        signature: signature,
      );

      if (apiRes.isSuccess) {
        state = CheckInSuccess(
          sessionId: sessionId,
          serverTime: apiRes.verifiedAt,
          rssi: meanRssi.round(),
        );
      } else if (apiRes.statusCode == 403) {
        state = const CheckInError(CodeRejectedFailure());
      } else {
        state = CheckInError(UnknownBleFailure(apiRes.errorMessage ?? 'Attendance verification failed on server.'));
      }
    } catch (e) {
      state = CheckInError(UnknownBleFailure('Backend attendance connection failed: $e'));
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
    apiService: ref.watch(attendanceApiServiceProvider),
  );
});
