import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Admin approval screen — lists pending verification users and lets
/// an admin approve or reject them.
///
/// Access is guarded by the Firebase Auth custom claim `role: admin`.
/// If the current user doesn't have this claim, a "Not Authorized"
/// message is shown instead.
class AdminApprovalScreen extends StatefulWidget {
  const AdminApprovalScreen({super.key});

  @override
  State<AdminApprovalScreen> createState() => _AdminApprovalScreenState();
}

class _AdminApprovalScreenState extends State<AdminApprovalScreen> {
  bool _isAdmin = false;
  bool _checkingAuth = true;

  @override
  void initState() {
    super.initState();
    _checkAdminClaim();
  }

  Future<void> _checkAdminClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isAdmin = false;
        _checkingAuth = false;
      });
      return;
    }

    // Force refresh to get latest custom claims
    final idTokenResult = await user.getIdTokenResult(true);
    final role = idTokenResult.claims?['role'];
    setState(() {
      _isAdmin = role == 'admin';
      _checkingAuth = false;
    });
  }

  Future<void> _updateUserStatus(String uid, String newStatus) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'status': newStatus,
      'verifiedAt': FieldValue.serverTimestamp(),
      'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_checkingAuth) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Not Authorized',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'You need admin privileges to access this page.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Panel'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.pending_actions), text: 'Pending'),
              Tab(icon: Icon(Icons.people_outline), text: 'Manage Roles'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Pending Approvals
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('status', isEqualTo: 'pending_verification')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading users: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 64, color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'No pending approvals',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Profile photo
                            CircleAvatar(
                              radius: 28,
                              backgroundImage: data['photoUrl'] != null
                                  ? NetworkImage(data['photoUrl'])
                                  : null,
                              child: data['photoUrl'] == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            const SizedBox(width: 16),

                            // User info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    data['name'] ?? 'Unknown',
                                    style: Theme.of(context).textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${data['rollNo'] ?? '—'} · ${(data['role'] ?? 'unknown').toString().toUpperCase()}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    data['email'] ?? '',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                            color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),

                            // Approve / Reject buttons
                            Column(
                              children: [
                                IconButton.filled(
                                  onPressed: () =>
                                      _updateUserStatus(uid, 'verified'),
                                  icon: const Icon(Icons.check),
                                  tooltip: 'Approve',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                IconButton.outlined(
                                  onPressed: () =>
                                      _updateUserStatus(uid, 'rejected'),
                                  icon: const Icon(Icons.close),
                                  tooltip: 'Reject',
                                  style: IconButton.styleFrom(
                                    foregroundColor: colorScheme.error,
                                  ),
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

            // Tab 2: Manage Roles
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('status', isEqualTo: 'verified')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading users: ${snapshot.error}'),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 64, color: colorScheme.secondary),
                        const SizedBox(height: 16),
                        Text(
                          'No verified users found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;
                    final currentRole = data['role'] ?? 'student';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: data['photoUrl'] != null
                              ? NetworkImage(data['photoUrl'])
                              : null,
                          child: data['photoUrl'] == null
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          data['name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${data['rollNo'] ?? '—'} · Role: ${currentRole.toString().toUpperCase()}',
                        ),
                        trailing: PopupMenuButton<String>(
                          initialValue: currentRole,
                          icon: const Icon(Icons.manage_accounts),
                          tooltip: 'Change Role',
                          onSelected: (role) async {
                            try {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .update({'role': role});
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Updated role of ${data['name']} to ${role.toUpperCase()}'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Failed to update role: $e')),
                                );
                              }
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'student',
                              child: Text('Student'),
                            ),
                            const PopupMenuItem(
                              value: 'faculty',
                              child: Text('Faculty'),
                            ),
                            const PopupMenuItem(
                              value: 'mentor',
                              child: Text('Mentor'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
