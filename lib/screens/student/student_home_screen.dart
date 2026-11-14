import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../ble/student_checkin_controller.dart';
import '../../models/attendance_session.dart';
import '../../models/enrollment.dart';
import '../../providers/auth_provider.dart';

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final checkInState = ref.watch(studentCheckInControllerProvider);
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final enrollmentsStream = FirebaseFirestore.instance
        .collection('enrollments')
        .where('studentUid', isEqualTo: user.uid)
        .snapshots()
        .map((s) => s.docs.map(Enrollment.fromDoc).toList());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
        actions: [
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Student Welcome Card
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
                              fontSize: 20,
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

            // Check-in State Banner / Feedback
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

            // Enrolled Courses & Open Sessions
            Text(
              'Enrolled Courses & Active Sessions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            StreamBuilder<List<Enrollment>>(
              stream: enrollmentsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
                }

                final enrollments = snapshot.data ?? [];
                if (enrollments.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.class_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No course enrollments found',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Contact your academic department coordinator to be enrolled in courses.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: enrollments.map((enrollment) {
                    return _EnrolledCourseCard(
                      enrollment: enrollment,
                      studentUid: user.uid,
                      remoteDeviceId: profile?.deviceId,
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 16),
            // Attendance History Navigation Card
            Card(
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined, color: Color(0xFF283593)),
                title: const Text('My Attendance History'),
                subtitle: const Text('View verified proximity attendance log'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/student/history'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EnrolledCourseCard extends ConsumerWidget {
  final Enrollment enrollment;
  final String studentUid;
  final String? remoteDeviceId;

  const _EnrolledCourseCard({
    required this.enrollment,
    required this.studentUid,
    required this.remoteDeviceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkInState = ref.watch(studentCheckInControllerProvider);
    final isBusy = checkInState is CheckInBiometricsPending ||
        checkInState is CheckInScanning ||
        checkInState is CheckInSubmitting;

    // Single equality query per course (no whereIn)
    final openSessionStream = FirebaseFirestore.instance
        .collection('sessions')
        .where('courseId', isEqualTo: enrollment.courseId)
        .where('status', isEqualTo: 'open')
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty ? AttendanceSession.fromDoc(s.docs.first) : null);

    return StreamBuilder<AttendanceSession?>(
      stream: openSessionStream,
      builder: (context, snapshot) {
        final session = snapshot.data;
        final hasActiveSession = session != null && session.isOpen;

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
                      label: Text(enrollment.courseId),
                      backgroundColor: Colors.indigo.shade50,
                      labelStyle: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold),
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
                const SizedBox(height: 8),
                Text(
                  'Course ID: ${enrollment.courseId}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Enrolled as ${enrollment.studentName} (${enrollment.rollNo})',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                if (hasActiveSession) ...[
                  const SizedBox(height: 16),
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
                                  ? 'Submitting Proof...'
                                  : 'Scan & Mark Attendance',
                    ),
                    onPressed: isBusy
                        ? null
                        : () {
                            ref
                                .read(studentCheckInControllerProvider.notifier)
                                .executeCheckIn(
                                  sessionId: session.id,
                                  studentUid: studentUid,
                                  remoteDeviceId: remoteDeviceId,
                                );
                          },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
