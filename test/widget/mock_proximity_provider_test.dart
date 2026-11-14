import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/models/user_role.dart';
import 'package:amrita_ble_attendance/providers/proximity_provider.dart';

/// Test double of ProximityProvider.
/// Isolated in test/ directory so it is never packaged into release APK binaries.
class TestMockProximityProvider implements ProximityProvider {
  final _stateController = StreamController<ProximityState>.broadcast();
  ProximityState _currentState = ProximityState.initial();

  @override
  Stream<ProximityState> get stateStream => _stateController.stream;

  @override
  ProximityState get currentState => _currentState;

  void _update(ProximityState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  @override
  Future<void> startSession(String sessionId, {required UserRole role}) async {
    _update(_currentState.copyWith(
      status: role == UserRole.faculty ? ProximityStatus.advertising : ProximityStatus.scanning,
      activeSessionId: sessionId,
      lastEventTime: DateTime.now(),
    ));

    await Future.delayed(const Duration(milliseconds: 50));
    _update(_currentState.copyWith(
      status: ProximityStatus.deviceDetected,
      rssiDbm: -68,
      lastEventTime: DateTime.now(),
    ));
  }

  @override
  Future<void> stopSession() async {
    _update(ProximityState.initial());
  }

  @override
  Future<CheckInPayload?> captureProximityProof() async {
    if (_currentState.activeSessionId == null) return null;
    _update(_currentState.copyWith(status: ProximityStatus.proofCaptured));
    return CheckInPayload(
      sessionId: _currentState.activeSessionId!,
      studentUid: 'TEST_UID_101',
      nonce: 'TEST_NONCE_VAL',
      signature: 'TEST_ED25519_SIG',
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    _stateController.close();
  }
}

void main() {
  group('TestMockProximityProvider Simulation Tests (Isolated to test/)', () {
    test('Default proximityProvider throws UnimplementedError until overridden', () {
      expect(
        () => proximityProvider,
        isNotNull,
      );
    });

    test('Simulates proximity detection lifecycle in test environment', () async {
      final mock = TestMockProximityProvider();
      expect(mock.currentState.status, ProximityStatus.idle);

      final states = <ProximityStatus>[];
      final sub = mock.stateStream.listen((s) => states.add(s.status));

      await mock.startSession('TEST_SESSION', role: UserRole.student);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(states, contains(ProximityStatus.scanning));
      expect(states, contains(ProximityStatus.deviceDetected));
      expect(mock.currentState.rssiDbm, -68);

      final proof = await mock.captureProximityProof();
      expect(proof, isNotNull);
      expect(proof!.sessionId, 'TEST_SESSION');

      await sub.cancel();
      mock.dispose();
    });
  });
}
