import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../ble/beacon_broadcaster.dart';
import '../../ble/code_rotator.dart';
import '../../ble/flutter_ble_peripheral_broadcaster.dart';
import '../../services/attendance_api_service.dart';
import '../../models/attendance_record.dart';
import '../../models/attendance_session.dart';
import '../../models/enrollment.dart';

class FacultySessionScreen extends ConsumerStatefulWidget {
  final String courseId;
  final String courseName;

  const FacultySessionScreen({
    super.key,
    required this.courseId,
    required this.courseName,
  });

  @override
  ConsumerState<FacultySessionScreen> createState() => _FacultySessionScreenState();
}

class _FacultySessionScreenState extends ConsumerState<FacultySessionScreen> {
  AttendanceSession? _currentSession;
  CodeRotator? _codeRotator;
  BeaconBroadcaster? _broadcaster;

  Timer? _countdownTimer;
  int _secondsRemaining = 0;
  bool _isCreatingSession = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _broadcaster = FlutterBlePeripheralBroadcaster();
    _initializeOrStartSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _codeRotator?.dispose();
    super.dispose();
  }

  Future<void> _initializeOrStartSession() async {
    setState(() {
      _isCreatingSession = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isCreatingSession = false;
        _errorMessage = 'Authentication required. Please sign in again.';
      });
      return;
    }

    try {
      // 1. Authoritative Backend Session Creation (PostgreSQL MUST be the sole authority)
      final apiService = ref.read(attendanceApiServiceProvider);
      final apiSession = await apiService.startSession(
        courseId: widget.courseId,
        roomLabel: 'Classroom',
        durationMinutes: 30,
        rssiThreshold: -75,
      );

      if (apiSession == null) {
        if (!mounted) return;
        setState(() {
          _isCreatingSession = false;
          _errorMessage =
              'Failed to start authoritative attendance session on backend server. Cannot broadcast attendance without cryptographic verification token.';
        });
        return;
      }

      final backendSessionId = apiSession['id'] as String?;
      final sessionSecret = apiSession['ephemeral_token'] as String?;
      if (backendSessionId == null || sessionSecret == null || sessionSecret.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isCreatingSession = false;
          _errorMessage =
              'Backend session returned invalid session parameters. Cryptographic session ID and secret are mandatory.';
        });
        return;
      }

      // 2. Parse timestamps from backend
      final now = DateTime.now();
      DateTime endsAt = now.add(const Duration(minutes: 30));
      if (apiSession['closes_at'] != null) {
        final parsedClosesAt = DateTime.tryParse(apiSession['closes_at'] as String);
        if (parsedClosesAt != null) {
          endsAt = parsedClosesAt.toLocal();
        }
      }

      // 3. Close any stale previously open sessions in Firestore projection for this course
      try {
        final staleSessions = await FirebaseFirestore.instance
            .collection('sessions')
            .where('courseId', isEqualTo: widget.courseId)
            .where('facultyId', isEqualTo: user.uid)
            .where('status', isEqualTo: 'open')
            .get();
        for (final doc in staleSessions.docs) {
          if (doc.id != backendSessionId) {
            await doc.reference.update({'status': 'closed'});
          }
        }
      } catch (_) {}

      // 4. Project PostgreSQL session into Firestore using the EXACT backend session ID
      final docRef = FirebaseFirestore.instance.collection('sessions').doc(backendSessionId);
      await docRef.set({
        'courseId': widget.courseId,
        'facultyId': user.uid,
        'startedAt': FieldValue.serverTimestamp(),
        'endsAt': Timestamp.fromDate(endsAt),
        'status': 'open',
        'backendSessionId': backendSessionId,
      }, SetOptions(merge: true));

      final session = AttendanceSession(
        id: backendSessionId,
        courseId: widget.courseId,
        facultyId: user.uid,
        startedAt: now,
        endsAt: endsAt,
        status: 'open',
      );

      if (!mounted) return;
      setState(() {
        _currentSession = session;
        _secondsRemaining = session.remainingSeconds;
        _isCreatingSession = false;
      });

      // 5. Start CodeRotator with Authoritative Session ID and Mandatory Secret
      _codeRotator?.dispose();
      _codeRotator = CodeRotator(
        sessionId: backendSessionId,
        sessionSecret: sessionSecret,
        broadcaster: _broadcaster!,
      );
      await _codeRotator!.start();

      // 6. Start countdown timer
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        final rem = _currentSession?.remainingSeconds ?? 0;
        setState(() => _secondsRemaining = rem);
        if (rem <= 0) {
          timer.cancel();
          _closeSession();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCreatingSession = false;
          _errorMessage = 'Failed to initialize session: $e';
        });
      }
    }
  }

  Future<void> _closeSession() async {
    if (_currentSession == null) return;
    try {
      final apiService = ref.read(attendanceApiServiceProvider);
      await apiService.stopSession(_currentSession!.id);

      await FirebaseFirestore.instance
          .collection('sessions')
          .doc(_currentSession!.id)
          .update({'status': 'closed'});
      await _codeRotator?.stop();

      if (mounted) {
        setState(() {
          _secondsRemaining = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session closed. Attendance finalized.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error closing session: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reopenNewSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await _closeSession();
    await _initializeOrStartSession();
  }

  Future<void> _promptManualOverride(Enrollment enrollment) async {
    final reasonController = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentSession == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manual Override: ${enrollment.studentName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Roll: ${enrollment.rollNo}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Mandatory Reason (min 3 chars)',
                hintText: 'e.g. Phone battery died / verified present',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().length >= 3) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Confirm Override'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final reason = reasonController.text.trim();
        await FirebaseFirestore.instance
            .collection('sessions')
            .doc(_currentSession!.id)
            .collection('attendance')
            .doc(enrollment.studentUid)
            .set({
          'studentUid': enrollment.studentUid,
          'markedAt': FieldValue.serverTimestamp(),
          'method': 'manual',
          'markedBy': user.uid,
          'reason': reason,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Manual override recorded for ${enrollment.studentName}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Override failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCreatingSession) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.courseName)),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initializing Attendance Beacon...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.courseName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initializeOrStartSession,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isSessionActive = (_currentSession?.isOpen ?? false) && _secondsRemaining > 0;
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    // Streams for live roster: Enrollments + Attendance
    final enrollmentsStream = FirebaseFirestore.instance
        .collection('enrollments')
        .where('courseId', isEqualTo: widget.courseId)
        .snapshots()
        .map((s) => s.docs.map(Enrollment.fromDoc).toList());

    final attendanceStream = _currentSession != null
        ? FirebaseFirestore.instance
            .collection('sessions')
            .doc(_currentSession!.id)
            .collection('attendance')
            .snapshots()
            .map((s) => s.docs.map(AttendanceRecord.fromDoc).toList())
        : Stream.value(<AttendanceRecord>[]);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/faculty'),
        ),
      ),
      body: StreamBuilder<List<Enrollment>>(
        stream: enrollmentsStream,
        builder: (context, enrollSnapshot) {
          final enrollments = enrollSnapshot.data ?? [];

          return StreamBuilder<List<AttendanceRecord>>(
            stream: attendanceStream,
            builder: (context, attendSnapshot) {
              final records = attendSnapshot.data ?? [];
              final attendanceByUid = {for (final r in records) r.studentUid: r};

              final checkedInCount = records.length;

              return Column(
                children: [
                  // Real Beacon Health & Telemetry Status Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: isSessionActive ? const Color(0xFF283593) : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: isSessionActive ? Colors.greenAccent : Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isSessionActive ? 'BROADCASTING BEACON' : 'SESSION CLOSED',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              isSessionActive ? '$minutes:$seconds left' : 'Expired',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Present: $checkedInCount / ${enrollments.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isSessionActive)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white70),
                                ),
                                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                                label: const Text('Close Session'),
                                onPressed: _closeSession,
                              )
                            else
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.replay, size: 18),
                                label: const Text('Start New Session'),
                                onPressed: _reopenNewSession,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Warning notice regarding backgrounding
                  if (isSessionActive)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Keep screen awake. Backgrounding this app pauses the BLE beacon.',
                              style: TextStyle(fontSize: 12, color: Colors.brown),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Classroom Live Roster',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          '${enrollments.length} Enrolled',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),

                  // Roster List
                  Expanded(
                    child: enrollments.isEmpty
                        ? Center(
                            child: Text(
                              'No students enrolled in this course yet.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: enrollments.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final student = enrollments[index];
                              final record = attendanceByUid[student.studentUid];
                              final isCheckedIn = record != null;

                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isCheckedIn
                                        ? Colors.green.shade100
                                        : Colors.grey.shade200,
                                    child: Icon(
                                      isCheckedIn ? Icons.check : Icons.person_outline,
                                      color: isCheckedIn ? Colors.green.shade800 : Colors.grey,
                                    ),
                                  ),
                                  title: Text(
                                    student.studentName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    '${student.rollNo} • ${isCheckedIn ? (record.isBle ? "BLE Proximity (${record.rssi} dBm)" : "Manual: ${record.reason}") : "Absent"}',
                                    style: TextStyle(
                                      color: isCheckedIn ? Colors.green.shade800 : Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: isSessionActive
                                      ? TextButton(
                                          onPressed: () => _promptManualOverride(student),
                                          child: Text(isCheckedIn ? 'Edit' : 'Override'),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
