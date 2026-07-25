import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_broadcast_screen.dart';
import 'student_history_screen.dart';
import 'faculty_session_screen.dart';
import 'session_history_screen.dart';
import 'admin_approval_screen.dart';
import '../services/auth_service.dart';

/// Role selection screen — now backed by the authenticated user's
/// Firestore profile. Routes to the appropriate screens based on role.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              await authService.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future:
            FirebaseFirestore.instance.collection('users').doc(user?.uid).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final role = userData['role'] ?? 'student';
          final name = userData['name'] ?? 'User';

          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Welcome header
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: userData['photoUrl'] != null
                        ? NetworkImage(userData['photoUrl'])
                        : null,
                    child: userData['photoUrl'] == null
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Welcome, $name',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Role-specific actions
                  if (role == 'student') ...[
                    _ActionCard(
                      icon: Icons.bluetooth,
                      title: 'Mark Attendance',
                      subtitle: 'Broadcast your BLE signal to mark present',
                      color: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StudentBroadcastScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.history,
                      title: 'Attendance History',
                      subtitle: 'View your attendance records & percentages',
                      color: Colors.indigo,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StudentHistoryScreen()),
                      ),
                    ),
                  ],

                  if (role == 'faculty' || role == 'mentor') ...[
                    _ActionCard(
                      icon: Icons.play_circle_filled,
                      title: 'Start Attendance Session',
                      subtitle: 'Open a BLE attendance window for your class',
                      color: Colors.green,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const FacultySessionScreen()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.list_alt,
                      title: 'Session History',
                      subtitle: 'View past sessions & edit attendance',
                      color: Colors.indigo,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SessionHistoryScreen()),
                      ),
                    ),
                  ],

                  // Admin access (shown to admins only, checked via custom claim)
                  const SizedBox(height: 12),
                  FutureBuilder<IdTokenResult>(
                    future: user?.getIdTokenResult(),
                    builder: (context, tokenSnap) {
                      final isAdmin =
                          tokenSnap.data?.claims?['role'] == 'admin';
                      if (!isAdmin) return const SizedBox.shrink();

                      return _ActionCard(
                        icon: Icons.admin_panel_settings,
                        title: 'Admin — Approve Users',
                        subtitle: 'Review and approve pending registrations',
                        color: Colors.orange,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AdminApprovalScreen()),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
