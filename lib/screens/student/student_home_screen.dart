import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../ble/student_checkin_controller.dart';
import '../../models/attendance_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_api_service.dart';

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _disputes = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _fetchAuthoritativeData();
  }

  Future<void> _fetchAuthoritativeData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final api = ref.read(attendanceApiServiceProvider);
      final results = await Future.wait([
        api.getCourses(),
        api.getMyAttendanceHistory(),
        api.getDisputes(),
      ]);

      if (mounted) {
        setState(() {
          _courses = results[0];
          _history = results[1];
          _disputes = results[2];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load attendance records: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showSubmitDisputeDialog(String sessionId, String courseCode) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Attendance Issue ($courseCode)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If you were present in class but missed the BLE window due to radio interference or battery, submit a grievance for faculty review.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason for Grievance',
                hintText: 'e.g. Phone Bluetooth rebooted; seated in row 3.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().length >= 5) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Submit Request'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final reason = reasonController.text.trim();
      final api = ref.read(attendanceApiServiceProvider);
      final ok = await api.submitDispute(sessionId: sessionId, reason: reason);
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance correction request submitted for faculty review.'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchAuthoritativeData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit dispute. A pending dispute may already exist.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final checkInState = ref.watch(studentCheckInControllerProvider);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Attendance Calculations
    final attendedCount = _history.where((r) => r['status'] == 'present' || r['status'] == 'present_override').length;
    final totalConducted = _history.isEmpty ? 1 : _history.length;
    final double attendancePct = (attendedCount / totalConducted) * 100.0;

    int safeSkips = 0;
    int classesNeeded = 0;
    String complianceStatus = 'Good Standing';
    Color complianceColor = Colors.green;

    if (attendancePct >= 75.0) {
      safeSkips = ((attendedCount - 0.75 * totalConducted) / 0.75).floor();
      if (safeSkips < 0) safeSkips = 0;
      complianceStatus = 'Eligible (>= 75%)';
      complianceColor = Colors.green;
    } else {
      classesNeeded = ((0.75 * totalConducted - attendedCount) / 0.25).ceil();
      if (classesNeeded < 0) classesNeeded = 0;
      if (attendancePct >= 65.0) {
        complianceStatus = 'Condonable (65-74%)';
        complianceColor = Colors.amber.shade800;
      } else {
        complianceStatus = 'Critical Shortage (FA Risk)';
        complianceColor = Colors.red;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Attendance Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Attendance',
            onPressed: _fetchAuthoritativeData,
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Attendance History',
            onPressed: () => context.go('/student/history'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAuthoritativeData,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. Student Identity Header Card
              Card(
                color: const Color(0xFF283593),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.school, color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile?.fullName ?? 'Student',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (profile?.rollNo != null)
                              Text(
                                'Roll No: ${profile!.rollNo}',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            Text(
                              profile?.email ?? '',
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 2. Attendance KPI Metric Cards
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        child: Column(
                          children: [
                            Text(
                              '${attendancePct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: complianceColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              complianceStatus,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: complianceColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        child: Column(
                          children: [
                            Text(
                              attendancePct >= 75.0 ? '$safeSkips' : '$classesNeeded',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: attendancePct >= 75.0 ? Colors.indigo : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              attendancePct >= 75.0 ? 'Safe Skips Left' : 'Classes Needed',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                        child: Column(
                          children: [
                            Text(
                              '$attendedCount / $totalConducted',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Classes Attended',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Live Check-In State Feedback
              if (checkInState is CheckInError)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          checkInState.failure.message,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                )
              else if (checkInState is CheckInSuccess)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Attendance Verified & Marked Present!',
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'Recorded via BLE (${checkInState.rssi} dBm) at ${checkInState.serverTime.hour}:${checkInState.serverTime.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(color: Colors.green.shade800, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 4. Enrolled Courses Section
              Text(
                'My Registered Courses',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              else if (_loadError != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 40, color: Colors.orange),
                        const SizedBox(height: 8),
                        Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 12),
                        ElevatedButton(onPressed: _fetchAuthoritativeData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              else if (_courses.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.class_outlined, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'No registered courses found',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Contact your faculty or academic coordinator to be enrolled in courses.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._courses.map((course) {
                  final courseId = course['id'] as String;
                  final courseCode = course['code'] as String;
                  final courseName = course['name'] as String;
                  final facultyName = course['faculty_name'] as String? ?? 'Faculty';

                  // Live active session stream for this course
                  final openSessionStream = FirebaseFirestore.instance
                      .collection('sessions')
                      .where('courseId', isEqualTo: courseId)
                      .where('status', isEqualTo: 'open')
                      .limit(1)
                      .snapshots()
                      .map((s) => s.docs.isNotEmpty ? AttendanceSession.fromDoc(s.docs.first) : null);

                  return StreamBuilder<AttendanceSession?>(
                    stream: openSessionStream,
                    builder: (context, snapshot) {
                      final session = snapshot.data;
                      final hasActiveSession = session != null && session.isOpen;

                      final isBusy = checkInState is CheckInBiometricsPending ||
                          checkInState is CheckInScanning ||
                          checkInState is CheckInSubmitting;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Chip(
                                    label: Text(courseCode),
                                    backgroundColor: Colors.indigo.shade50,
                                    labelStyle: TextStyle(
                                      color: Colors.indigo.shade900,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (hasActiveSession)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.sensors, size: 14, color: Colors.green),
                                          SizedBox(width: 4),
                                          Text(
                                            'SESSION ACTIVE',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Text(
                                      'No active session',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                courseName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Instructor: $facultyName',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                              if (hasActiveSession) ...[
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF283593),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  icon: isBusy
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.sensors),
                                  label: Text(
                                    checkInState is CheckInBiometricsPending
                                        ? 'Scan Fingerprint...'
                                        : checkInState is CheckInScanning
                                            ? 'Searching for Faculty Beacon...'
                                            : checkInState is CheckInSubmitting
                                                ? 'Submitting Cryptographic Proof...'
                                                : 'Scan & Mark Attendance',
                                  ),
                                  onPressed: isBusy
                                      ? null
                                      : () {
                                          ref
                                              .read(studentCheckInControllerProvider.notifier)
                                              .executeCheckIn(
                                                sessionId: session.id,
                                                studentUid: user.uid,
                                                remoteDeviceId: profile?.deviceId,
                                              );
                                        },
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(Icons.help_outline, size: 14),
                                    label: const Text('Missed Beacon? Report Issue', style: TextStyle(fontSize: 11)),
                                    onPressed: () => _showSubmitDisputeDialog(session.id, courseCode),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),

              const SizedBox(height: 16),

              // 5. Attendance Grievances & Disputes Status
              if (_disputes.isNotEmpty) ...[
                Text(
                  'My Attendance Correction Requests',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._disputes.map((d) {
                  final status = d['status'] as String? ?? 'pending';
                  final isApproved = status == 'approved';
                  final isRejected = status == 'rejected';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        isApproved
                            ? Icons.check_circle
                            : isRejected
                                ? Icons.cancel
                                : Icons.hourglass_top,
                        color: isApproved
                            ? Colors.green
                            : isRejected
                                ? Colors.red
                                : Colors.amber.shade800,
                      ),
                      title: Text(
                        '${d['course_code']}: ${d['reason']}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: d['resolution_notes'] != null
                          ? Text(
                              'Faculty Note: ${d['resolution_notes']}',
                              style: TextStyle(fontSize: 11, color: isApproved ? Colors.green.shade800 : Colors.red.shade800),
                            )
                          : null,
                      trailing: Chip(
                        label: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isApproved
                                ? Colors.green.shade900
                                : isRejected
                                    ? Colors.red.shade900
                                    : Colors.amber.shade900,
                          ),
                        ),
                        backgroundColor: isApproved
                            ? Colors.green.shade50
                            : isRejected
                                ? Colors.red.shade50
                                : Colors.amber.shade50,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 16),
              ],

              // 6. Navigation to Attendance Log Card
              Card(
                child: ListTile(
                  leading: const Icon(Icons.analytics_outlined, color: Color(0xFF283593)),
                  title: const Text('Detailed Attendance Log'),
                  subtitle: const Text('View verified records and submit grievances'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/student/history'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
