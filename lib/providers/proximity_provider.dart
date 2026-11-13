import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_role.dart';
import '../services/default_proximity_service.dart';

enum ProximityStatus {
  idle,
  advertising,
  scanning,
  deviceDetected,
  proofCaptured,
  error,
}

class ProximityState {
  final ProximityStatus status;
  final String? activeSessionId;
  final int rssiDbm;
  final String? errorMessage;
  final DateTime? lastEventTime;

  const ProximityState({
    required this.status,
    this.activeSessionId,
    this.rssiDbm = 0,
    this.errorMessage,
    this.lastEventTime,
  });

  factory ProximityState.initial() => const ProximityState(status: ProximityStatus.idle);

  ProximityState copyWith({
    ProximityStatus? status,
    String? activeSessionId,
    int? rssiDbm,
    String? errorMessage,
    DateTime? lastEventTime,
  }) {
    return ProximityState(
      status: status ?? this.status,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      rssiDbm: rssiDbm ?? this.rssiDbm,
      errorMessage: errorMessage ?? this.errorMessage,
      lastEventTime: lastEventTime ?? this.lastEventTime,
    );
  }
}

class CheckInPayload {
  final String sessionId;
  final String studentUid;
  final String nonce;
  final String signature;
  final DateTime timestamp;

  const CheckInPayload({
    required this.sessionId,
    required this.studentUid,
    required this.nonce,
    required this.signature,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'student_uid': studentUid,
        'nonce': nonce,
        'signature': signature,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Abstract contract for BLE hardware proximity detection.
abstract class ProximityProvider {
  Stream<ProximityState> get stateStream;
  ProximityState get currentState;

  Future<void> startSession(String sessionId, {required UserRole role});
  Future<void> stopSession();
  Future<CheckInPayload?> captureProximityProof();
}

/// Global Riverpod provider for ProximityProvider.
/// Uses DefaultProximityService for hardware BLE operations and RF simulation.
final proximityProvider = Provider<ProximityProvider>((ref) {
  final service = DefaultProximityService();
  ref.onDispose(() => service.dispose());
  return service;
});
