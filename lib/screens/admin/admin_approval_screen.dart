import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/admin_approval_repository.dart';

class AdminApprovalScreen extends ConsumerStatefulWidget {
  const AdminApprovalScreen({super.key});

  @override
  ConsumerState<AdminApprovalScreen> createState() => _AdminApprovalScreenState();
}

class _AdminApprovalScreenState extends ConsumerState<AdminApprovalScreen> {
  bool _isProcessing = false;

  Future<void> _handleDecision(String uid, ApprovalDecision decision, String userName) async {
    String? reason;
    if (decision == ApprovalDecision.reject) {
      reason = await _promptRejectionReason();
      if (reason == null) return; // user cancelled
    }

    setState(() => _isProcessing = true);
    try {
      final repo = ref.read(adminApprovalRepositoryProvider);
      await repo.reviewUser(uid: uid, decision: decision, reason: reason);

      if (mounted) {
        final actionName = decision == ApprovalDecision.approve ? 'approved' : 'rejected';
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

  Future<String?> _promptRejectionReason() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rejection Reason'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter reason (e.g. Unverified enrollment)',
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

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(adminApprovalRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Verification Portal'),
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
      body: StreamBuilder<List<PendingUser>>(
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
                  const Text(
                    'All caught up!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No accounts pending verification at this time.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
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
    );
  }
}
