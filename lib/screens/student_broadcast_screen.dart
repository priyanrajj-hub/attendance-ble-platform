import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../ble/ble_advertiser.dart';
import '../ble/ble_constants.dart';
import '../services/session_service.dart';
import '../services/token_service.dart';
import '../models/attendance_session.dart';


/// Student screen — finds the current active session, fetches the
/// rotating HMAC token, and broadcasts a signed BLE payload.
///
/// The broadcast stops immediately if the app is backgrounded
/// (existing anti-cheat from Phase 0).
class StudentBroadcastScreen extends StatefulWidget {
  const StudentBroadcastScreen({super.key});

  @override
  State<StudentBroadcastScreen> createState() => _StudentBroadcastScreenState();
}

class _StudentBroadcastScreenState extends State<StudentBroadcastScreen>
    with WidgetsBindingObserver {
  final _advertiser = BleAdvertiser();
  final _sessionService = SessionService();

  bool _isBroadcasting = false;
  bool _searching = true;
  String _statusMessage = 'Searching for active session...';
  AttendanceSession? _session;
  Timer? _tokenRefreshTimer;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _findSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advertiser.stopAdvertising();
    _tokenRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isBroadcasting && state != AppLifecycleState.resumed) {
      _terminateSession('Session terminated — app was backgrounded.');
    }
  }

  Future<void> _findSession() async {
    setState(() => _searching = true);

    try {
      final session = await _sessionService.findActiveSession();
      if (!mounted) return;

      if (session == null) {
        setState(() {
          _searching = false;
          _statusMessage = 'No active attendance session found.\n'
              'Wait for your faculty to start one.';
        });
      } else {
        setState(() {
          _session = session;
          _searching = false;
          _statusMessage = 'Session found: ${session.subjectName}\n'
              'Tap "Start Broadcast" to mark your attendance.';
          _remainingSeconds = session.remainingSeconds;
        });
        _startCountdown();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _statusMessage = 'Error finding session: $e';
      });
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _session?.remainingSeconds ?? 0;
      if (remaining <= 0) {
        timer.cancel();
        _terminateSession('Session window has expired.');
        return;
      }
      setState(() => _remainingSeconds = remaining);
    });
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _startBroadcast() async {
    if (_session == null) return;

    final granted = await _ensurePermissions();
    if (!granted) {
      setState(() => _statusMessage = 'Bluetooth permissions required.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _statusMessage = 'Not logged in.');
      return;
    }

    // Generate signed payload and start advertising
    await _broadcastSignedPayload(user.uid);

    // Refresh token every 25 seconds (tokens rotate at 30-second boundaries)
    _tokenRefreshTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isBroadcasting && mounted) {
        _broadcastSignedPayload(user.uid);
      }
    });

    setState(() {
      _isBroadcasting = true;
      _statusMessage = 'Broadcasting attendance signal...\n'
          'Keep this app in the foreground.';
    });
  }

  Future<void> _broadcastSignedPayload(String uid) async {
    if (_session == null) return;

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getStudentToken')
          .call({'sessionId': _session!.sessionId});
      final token = result.data['token'] as String;

      // Stop and restart with new token
      await _advertiser.stopAdvertising();

      final payload = TokenService.encodeBlePayload(uid, token);

      // Use the existing advertiser with the signed payload
      await _advertiser.startAdvertisingWithPayload(
        Uint8List.fromList(payload),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to fetch signed BLE token: $e';
        });
      }
    }
  }


  Future<void> _terminateSession(String reason) async {
    await _advertiser.stopAdvertising();
    _tokenRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isBroadcasting = false;
      _statusMessage = reason;
    });
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Student — Attendance')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_searching)
              const Center(child: CircularProgressIndicator())
            else if (_session != null) ...[
              // Session info card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _isBroadcasting
                      ? Colors.green.withOpacity(0.1)
                      : colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: _isBroadcasting
                      ? Border.all(color: Colors.green, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      _isBroadcasting
                          ? Icons.bluetooth_connected
                          : Icons.class_outlined,
                      size: 48,
                      color: _isBroadcasting ? Colors.green : colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _session!.subjectName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      _session!.classId,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _formatTime(_remainingSeconds),
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _remainingSeconds < 60
                            ? Colors.red
                            : colorScheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text('remaining'),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (!_isBroadcasting)
                FilledButton.icon(
                  onPressed: _startBroadcast,
                  icon: const Icon(Icons.bluetooth),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Start Broadcast',
                        style: TextStyle(fontSize: 16)),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () =>
                      _terminateSession('Broadcasting stopped manually.'),
                  icon: const Icon(Icons.stop),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Stop', style: TextStyle(fontSize: 16)),
                  ),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error),
                ),
            ] else ...[
              Icon(Icons.search_off, size: 64, color: colorScheme.onSurfaceVariant),
            ],

            const SizedBox(height: 24),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _isBroadcasting
                    ? Colors.green[700]
                    : colorScheme.onSurfaceVariant,
              ),
            ),

            if (!_searching && _session == null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _findSession,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
