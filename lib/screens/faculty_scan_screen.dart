import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble/ble_scanner.dart';
import '../ble/ble_constants.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';
import '../services/session_service.dart';
import '../services/token_service.dart';

/// Faculty scan screen — scans for student BLE advertisements,
/// verifies HMAC tokens server-side, checks RSSI + dwell-time,
/// and marks students present.
class FacultyScanScreen extends StatefulWidget {
  final AttendanceSession session;

  const FacultyScanScreen({super.key, required this.session});

  @override
  State<FacultyScanScreen> createState() => _FacultyScanScreenState();
}

class _FacultyScanScreenState extends State<FacultyScanScreen> {
  final _scanner = BleScanner();
  final _sessionService = SessionService();
  StreamSubscription<List<ScanResult>>? _subscription;
  bool _isScanning = false;

  // Track detected students with their scan metadata
  final Map<String, _DetectedStudent> _detected = {};

  /// Minimum RSSI to consider "in range" (calibrate per room).
  static const int rssiThreshold = -75;

  /// Minimum scan hits before marking present (dwell-time).
  static const int minScanCount = 3;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scanner.stopScan();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _startScan() async {
    final granted = await _ensurePermissions();
    if (!granted) return;

    setState(() => _isScanning = true);

    _subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _processResult(result);
      }
    });

    await FlutterBluePlus.startScan(
      withServices: [Guid(BleConstants.serviceUuid)],
      continuousUpdates: true,
    );
  }

  void _processResult(ScanResult result) {
    final manufacturerData = result.advertisementData.manufacturerData;
    final bytes = manufacturerData[BleConstants.manufacturerId];
    if (bytes == null || bytes.length < 16) return;

    // Decode the payload: [uid(8) | token(8)]
    final decoded = TokenService.decodeBlePayload(bytes);
    if (decoded == null) return;

    // Verify the HMAC token against the session secret
    // We only have a fragment (8 chars) — compare first 8 chars of the full token
    final expectedToken = TokenService.generateToken(
        widget.session.sessionId, widget.session.hmacSecret);
    final expectedFragment = expectedToken.substring(0, 8);

    final tokenValid = decoded.tokenFragment == expectedFragment;

    setState(() {
      final existing = _detected[decoded.uidPrefix];
      if (existing != null) {
        existing.scanCount++;
        existing.lastRssi = result.rssi;
        existing.lastSeen = DateTime.now();
        existing.tokenValid = tokenValid;
      } else {
        _detected[decoded.uidPrefix] = _DetectedStudent(
          uidPrefix: decoded.uidPrefix,
          scanCount: 1,
          lastRssi: result.rssi,
          lastSeen: DateTime.now(),
          tokenValid: tokenValid,
        );
      }
    });

    // Auto-mark present if conditions met
    if (tokenValid &&
        result.rssi >= rssiThreshold &&
        (_detected[decoded.uidPrefix]?.scanCount ?? 0) >= minScanCount) {
      _markPresent(decoded.uidPrefix, result.rssi, decoded.tokenFragment);
    }
  }

  Future<void> _markPresent(String uidPrefix, int rssi, String tokenFragment) async {
    final student = _detected[uidPrefix];
    if (student == null || student.markedPresent) return;

    student.markedPresent = true;

    try {
      await _sessionService.markPresent(
        sessionId: widget.session.sessionId,
        studentUid: uidPrefix,
        hmacToken: tokenFragment,
        rssi: rssi,
        scanCount: student.scanCount,
      );
    } catch (_) {
      student.markedPresent = false;
    }
    if (mounted) setState(() {});
  }


  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    await _subscription?.cancel();
    setState(() => _isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final students = _detected.values.toList()
      ..sort((a, b) => b.scanCount.compareTo(a.scanCount));

    final presentCount = students.where((s) => s.markedPresent).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Scanning — ${widget.session.subjectName}'),
        actions: [
          Chip(
            label: Text('$presentCount present'),
            backgroundColor: Colors.green.withOpacity(0.2),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isScanning
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isScanning) ...[
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Text('Scanning for student devices...',
                      style: TextStyle(color: colorScheme.onPrimaryContainer)),
                ] else
                  Text('Scan stopped.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),

          // Legend
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _legendDot(Colors.green, 'Present'),
                const SizedBox(width: 16),
                _legendDot(Colors.orange, 'Detecting...'),
                const SizedBox(width: 16),
                _legendDot(Colors.red, 'Invalid token'),
              ],
            ),
          ),

          // Student list
          Expanded(
            child: students.isEmpty
                ? const Center(child: Text('No students detected yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final s = students[index];
                      final ago =
                          DateTime.now().difference(s.lastSeen).inSeconds;

                      Color statusColor;
                      String statusText;
                      if (!s.tokenValid) {
                        statusColor = Colors.red;
                        statusText = 'Invalid Token';
                      } else if (s.markedPresent) {
                        statusColor = Colors.green;
                        statusText = 'Present ✓';
                      } else {
                        statusColor = Colors.orange;
                        statusText =
                            'Detecting (${s.scanCount}/$minScanCount scans)';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withOpacity(0.15),
                            child: Icon(
                              s.markedPresent
                                  ? Icons.check
                                  : Icons.bluetooth_searching,
                              color: statusColor,
                            ),
                          ),
                          title: Text(
                            s.uidPrefix,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                          subtitle: Text(
                            '$statusText · ${s.lastRssi} dBm · ${ago}s ago',
                          ),
                          trailing: Text(
                            '${s.scanCount}×',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _isScanning
                      ? OutlinedButton.icon(
                          onPressed: _stopScan,
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop Scan'),
                        )
                      : FilledButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Resume Scan'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _DetectedStudent {
  final String uidPrefix;
  int scanCount;
  int lastRssi;
  DateTime lastSeen;
  bool tokenValid;
  bool markedPresent;

  _DetectedStudent({
    required this.uidPrefix,
    required this.scanCount,
    required this.lastRssi,
    required this.lastSeen,
    required this.tokenValid,
    this.markedPresent = false,
  });
}
