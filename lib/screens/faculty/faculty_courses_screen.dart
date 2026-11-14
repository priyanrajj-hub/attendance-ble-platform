import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../services/attendance_api_service.dart';

class FacultyCoursesScreen extends ConsumerStatefulWidget {
  const FacultyCoursesScreen({super.key});

  @override
  ConsumerState<FacultyCoursesScreen> createState() => _FacultyCoursesScreenState();
}

class _FacultyCoursesScreenState extends ConsumerState<FacultyCoursesScreen> {
  List<Map<String, dynamic>> _courses = [];
  List<Map<String, dynamic>> _disputes = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFacultyData();
  }

  Future<void> _loadFacultyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(attendanceApiServiceProvider);
      final results = await Future.wait([
        api.getCourses(),
        api.getDisputes(),
      ]);

      if (mounted) {
        setState(() {
          _courses = results[0];
          _disputes = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load faculty portal data: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateCourseDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final termCtrl = TextEditingController(text: 'Fall 2026');

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Course'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Course Code',
                hintText: 'e.g. 19CSE450',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Course Name',
                hintText: 'e.g. Mobile Computing & IoT',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: termCtrl,
              decoration: const InputDecoration(
                labelText: 'Term / Semester',
                hintText: 'e.g. Fall 2026',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (codeCtrl.text.trim().isNotEmpty && nameCtrl.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (created == true && mounted) {
      final api = ref.read(attendanceApiServiceProvider);
      final res = await api.createCourse(
        code: codeCtrl.text.trim().toUpperCase(),
        name: nameCtrl.text.trim(),
        term: termCtrl.text.trim(),
      );

      if (mounted) {
        if (res != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Course ${res['code']} created successfully in PostgreSQL.'),
              backgroundColor: Colors.green,
            ),
          );
          _loadFacultyData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to create course. Ensure code is unique.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleDisputeResolution(Map<String, dynamic> dispute, String decision) async {
    final disputeId = dispute['id'] as String;
    final studentName = dispute['student_name'] as String? ?? 'Student';
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${decision == "approved" ? "Approve" : "Reject"} Grievance: $studentName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Student Reason: ${dispute['reason']}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Resolution Notes',
                hintText: 'e.g. Verified physical attendance via seat verification',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: decision == 'approved' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm ${decision.toUpperCase()}'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final api = ref.read(attendanceApiServiceProvider);
      final ok = await api.resolveDispute(
        disputeId: disputeId,
        decision: decision,
        resolutionNotes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : null,
      );

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dispute for $studentName marked $decision in PostgreSQL.'),
              backgroundColor: decision == 'approved' ? Colors.green : Colors.orange,
            ),
          );
          _loadFacultyData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update dispute.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pendingDisputes = _disputes.where((d) => d['status'] == 'pending').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create Course',
            onPressed: _showCreateCourseDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadFacultyData,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCourseDialog,
        backgroundColor: const Color(0xFF283593),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Course'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadFacultyData, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadFacultyData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 1. Faculty Welcome Card
                      Card(
                        color: const Color(0xFF283593),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white24,
                                child: Icon(Icons.co_present, color: Colors.white, size: 32),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile?.fullName ?? 'Faculty Member',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      profile?.email ?? '',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 2. Pending Attendance Grievances Section
                      if (pendingDisputes.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.gavel, color: Colors.orange, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Pending Attendance Grievances (${pendingDisputes.length})',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...pendingDisputes.map((d) {
                          return Card(
                            color: Colors.orange.shade50,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${d['student_name']} (${d['roll_number'] ?? d['course_code']})',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Chip(
                                        label: Text(d['course_code'] as String? ?? 'Course'),
                                        backgroundColor: Colors.white,
                                        labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Reason: ${d['reason']}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _handleDisputeResolution(d, 'rejected'),
                                        child: const Text('Reject', style: TextStyle(color: Colors.red)),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => _handleDisputeResolution(d, 'approved'),
                                        child: const Text('Approve Presence'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],

                      // 3. Assigned Courses
                      Text(
                        'Assigned Courses (${_courses.length})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (_courses.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text(
                                  'No courses created yet',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Click "New Course" below to initialize a course in PostgreSQL.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._courses.map((c) {
                          final courseId = c['id'] as String;
                          final code = c['code'] as String;
                          final name = c['name'] as String;
                          final enrolledCount = c['enrolled_count'] ?? 0;
                          final term = c['term'] ?? 'Fall 2026';

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
                                        label: Text(code),
                                        backgroundColor: Colors.indigo.shade50,
                                        labelStyle: TextStyle(
                                          color: Colors.indigo.shade900,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        '$enrolledCount Students • $term',
                                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    name,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF283593),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(42),
                                    ),
                                    icon: const Icon(Icons.podcasts),
                                    label: const Text('Start Attendance Session (BLE)'),
                                    onPressed: () {
                                      final title = Uri.encodeComponent(name);
                                      context.go('/faculty/session/$courseId?name=$title');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}
