import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/persona_switcher_sheet.dart';

class FacultyCoursesScreen extends ConsumerWidget {
  const FacultyCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;

    final courses = [
      {
        'id': 'CSE450',
        'code': '19CSE450',
        'title': 'Mobile Computing & BLE Architectures',
        'enrolled': 58,
        'room': 'Room 204',
      },
      {
        'id': 'CSE401',
        'code': '19CSE401',
        'title': 'Distributed Systems & Cloud Security',
        'enrolled': 62,
        'room': 'Lab 3',
      },
      {
        'id': 'CSE480',
        'code': '19CSE480',
        'title': 'Information Security & Cryptography',
        'enrolled': 45,
        'room': 'Seminar Hall 1',
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Portal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horizontal_circle_outlined),
            tooltip: 'Switch Persona',
            onPressed: () => showPersonaSwitcherModal(context, ref),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          Text(
            'Assigned Courses',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...courses.map((c) => Card(
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
                            label: Text(c['code'] as String),
                            backgroundColor: Colors.indigo.shade50,
                            labelStyle: TextStyle(
                              color: Colors.indigo.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${c['enrolled']} Students Enrolled',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c['title'] as String,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scheduled Venue: ${c['room']}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF283593),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(42),
                        ),
                        icon: const Icon(Icons.podcasts),
                        label: const Text('Start Attendance Session'),
                        onPressed: () {
                          final courseId = c['id'] as String;
                          final title = Uri.encodeComponent(c['title'] as String);
                          context.go('/faculty/session/$courseId?name=$title');
                        },
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
