import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen> {
  bool _isChecking = false;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // Periodically poll for server-side token claim refresh every 8 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _checkServerApproval());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  /// Forces a token refresh to retrieve custom claims stamped by the backend server
  Future<void> _checkServerApproval() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final tokenResult = await user.getIdTokenResult(true); // forceRefresh: true
      final statusClaim = tokenResult.claims?['status'] as String?;
      final roleClaim = tokenResult.claims?['role'] as String?;

      if (statusClaim == 'verified' && roleClaim != null && mounted) {
        _pollingTimer?.cancel();
        ref.invalidate(userProfileProvider);

        final role = UserRole.fromString(roleClaim);
        switch (role) {
          case UserRole.student:
            context.go('/student');
            break;
          case UserRole.faculty:
            context.go('/faculty');
            break;
          case UserRole.admin:
            context.go('/admin');
            break;
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Pending'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              _pollingTimer?.cancel();
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: profileAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading profile: $e')),
                data: (profile) {
                  if (profile == null) {
                    return const Center(child: Text('Profile record not found.'));
                  }

                  if (profile.isVerified) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      switch (profile.role) {
                        case UserRole.student:
                          context.go('/student');
                          break;
                        case UserRole.faculty:
                          context.go('/faculty');
                          break;
                        case UserRole.admin:
                          context.go('/admin');
                          break;
                      }
                    });
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.hourglass_top_outlined,
                        size: 80,
                        color: Colors.amber,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Approval Pending',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hello, ${profile.fullName}!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your ${profile.role.displayName} account (${profile.email}) is awaiting verification by an administrator.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.security, color: Colors.amber, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Security Policy Notice',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'To prevent spoofing and enforce attendance integrity, student accounts must be verified by faculty/admin before participating in BLE check-in.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        icon: _isChecking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.refresh),
                        label: const Text('Check Status (Force Refresh)'),
                        onPressed: _isChecking
                            ? null
                            : () async {
                                setState(() => _isChecking = true);
                                await _checkServerApproval();
                                if (mounted) setState(() => _isChecking = false);
                              },
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
