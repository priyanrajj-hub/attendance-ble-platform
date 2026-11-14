import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/course.dart';
import '../../models/enrollment.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/admin_approval_repository.dart';

class AdminApprovalScreen extends ConsumerStatefulWidget {
  const AdminApprovalScreen({super.key});

  @override
  ConsumerState<AdminApprovalScreen> createState() => _AdminApprovalScreenState();
}

class _AdminApprovalScreenState extends ConsumerState<AdminApprovalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _handleDecision(String uid, ApprovalDecision decision, String userName) async {
    String? reason;
    if (decision == ApprovalDecision.reject) {
      reason = await _promptRejectionReason();
      if (reason == null) return;
    }

    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(adminApprovalRepositoryProvider);
      await repo.reviewUser(uid: uid, decision: decision, reason: reason);

      if (mounted) {
        final actionName = decision == ApprovalDecision.approve
            ? 'approved'
            : decision == ApprovalDecision.reject
                ? 'rejected'
                : 'suspended';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$userName was $actionName successfully.'),
            backgroundColor: decision == ApprovalDecision.approve ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reviewing user: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleResetDevice(String uid, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Device Binding: $userName'),
        content: const Text(
          'This will clear the device UUID bound to this student, allowing them to bind a new hardware device on next check-in.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm Reset')),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await ref.read(adminApprovalRepositoryProvider).resetDevice(uid: uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Device binding reset for $userName')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reset failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<String?> _promptRejectionReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejection Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter reason (e.g. Unverified institutional record)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateCourseDialog() async {
    final codeCtrl = TextEditingController();
    final titleCtrl = TextEditingController();
    final roomCtrl = TextEditingController();
    final facultyUidCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Course'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Course Code (e.g. 19CSE450)')),
              const SizedBox(height: 12),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Course Title')),
              const SizedBox(height: 12),
              TextField(controller: roomCtrl, decoration: const InputDecoration(labelText: 'Room Venue (e.g. Room 204)')),
              const SizedBox(height: 12),
              TextField(controller: facultyUidCtrl, decoration: const InputDecoration(labelText: 'Faculty UID')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              final title = titleCtrl.text.trim();
              final room = roomCtrl.text.trim();
              final facultyUid = facultyUidCtrl.text.trim();

              if (code.isNotEmpty && title.isNotEmpty && room.isNotEmpty && facultyUid.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance.collection('courses').doc(code).set({
                    'code': code,
                    'title': title,
                    'room': room,
                    'facultyIds': [facultyUid],
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                }
              }
            },
            child: const Text('Create Course'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEnrollStudentDialog() async {
    final courseIdCtrl = TextEditingController();
    final studentUidCtrl = TextEditingController();
    final studentNameCtrl = TextEditingController();
    final rollNoCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enroll Student in Course'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: courseIdCtrl, decoration: const InputDecoration(labelText: 'Course Code/ID')),
              const SizedBox(height: 12),
              TextField(controller: studentUidCtrl, decoration: const InputDecoration(labelText: 'Student Auth UID')),
              const SizedBox(height: 12),
              TextField(controller: studentNameCtrl, decoration: const InputDecoration(labelText: 'Student Legal Name')),
              const SizedBox(height: 12),
              TextField(controller: rollNoCtrl, decoration: const InputDecoration(labelText: 'Student Roll No')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final courseId = courseIdCtrl.text.trim().toUpperCase();
              final studentUid = studentUidCtrl.text.trim();
              final studentName = studentNameCtrl.text.trim();
              final rollNo = rollNoCtrl.text.trim().toUpperCase();

              if (courseId.isNotEmpty && studentUid.isNotEmpty && studentName.isNotEmpty && rollNo.isNotEmpty) {
                try {
                  final eid = '${courseId}_$studentUid';
                  await FirebaseFirestore.instance.collection('enrollments').doc(eid).set({
                    'courseId': courseId,
                    'studentUid': studentUid,
                    'studentName': studentName,
                    'rollNo': rollNo,
                    'enrolledAt': FieldValue.serverTimestamp(),
                  });
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Enrollment failed: $e')));
                  }
                }
              }
            },
            child: const Text('Enroll Student'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminApprovalRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.how_to_reg), text: 'Verifications'),
            Tab(icon: Icon(Icons.school), text: 'Courses'),
            Tab(icon: Icon(Icons.group_add), text: 'Enrollments'),
          ],
        ),
        actions: [
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
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Pending User Verifications ──────────────────────────────
          StreamBuilder<List<PendingUser>>(
            stream: repo.watchPendingUsers(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error loading requests: ${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snapshot.data ?? [];
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 72, color: Colors.green.shade400),
                      const SizedBox(height: 16),
                      const Text('All caught up!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('No pending account verifications.', style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final user = users[index];

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: user.role.name == 'faculty'
                                    ? Colors.deepOrange
                                    : const Color(0xFF283593),
                                child: Icon(
                                  user.role.name == 'faculty' ? Icons.co_present : Icons.school,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.fullName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    Text(
                                      user.email,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                    if (user.rollNo != null)
                                      Text(
                                        'Roll: ${user.rollNo}',
                                        style: TextStyle(color: Colors.indigo.shade700, fontSize: 12, fontWeight: FontWeight.w500),
                                      ),
                                    if (user.deviceId != null)
                                      Text(
                                        'Bound Device: ${user.deviceId}',
                                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                      ),
                                  ],
                                ),
                              ),
                              Chip(
                                label: Text(user.role.displayName.toUpperCase()),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (user.deviceId != null)
                                TextButton(
                                  onPressed: () => _handleResetDevice(user.uid, user.fullName),
                                  child: const Text('Reset Device'),
                                ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: _isProcessing
                                    ? null
                                    : () => _handleDecision(
                                          user.uid,
                                          ApprovalDecision.reject,
                                          user.fullName,
                                        ),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isProcessing
                                    ? null
                                    : () => _handleDecision(
                                          user.uid,
                                          ApprovalDecision.approve,
                                          user.fullName,
                                        ),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),

          // ── Tab 2: Courses ─────────────────────────────────────────────────
          Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _showCreateCourseDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add Course'),
            ),
            body: StreamBuilder<List<Course>>(
              stream: FirebaseFirestore.instance
                  .collection('courses')
                  .snapshots()
                  .map((s) => s.docs.map(Course.fromDoc).toList()),
              builder: (context, snapshot) {
                final courses = snapshot.data ?? [];
                if (courses.isEmpty) {
                  return const Center(child: Text('No courses created yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final c = courses[index];
                    return Card(
                      child: ListTile(
                        title: Text('${c.code}: ${c.title}'),
                        subtitle: Text('Venue: ${c.room} • Faculty: ${c.facultyIds.join(", ")}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // ── Tab 3: Enrollments ─────────────────────────────────────────────
          Scaffold(
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _showEnrollStudentDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Enroll Student'),
            ),
            body: StreamBuilder<List<Enrollment>>(
              stream: FirebaseFirestore.instance
                  .collection('enrollments')
                  .snapshots()
                  .map((s) => s.docs.map(Enrollment.fromDoc).toList()),
              builder: (context, snapshot) {
                final enrollments = snapshot.data ?? [];
                if (enrollments.isEmpty) {
                  return const Center(child: Text('No student enrollments yet.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: enrollments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final e = enrollments[index];
                    return Card(
                      child: ListTile(
                        title: Text('${e.studentName} (${e.rollNo})'),
                        subtitle: Text('Course: ${e.courseId} • UID: ${e.studentUid}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
