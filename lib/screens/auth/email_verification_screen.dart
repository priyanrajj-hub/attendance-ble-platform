import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends ConsumerState<EmailVerificationScreen> {
  bool _isChecking = false;
  int _resendCooldownSeconds = 0;
  Timer? _pollTimer;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Quietly poll auth state every 4 seconds without SnackBar spam
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollVerificationStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollVerificationStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.reload();
        await user.getIdToken(true);
        if (user.emailVerified && mounted) {
          _pollTimer?.cancel();
          context.go('/pending-approval');
        }
      } catch (_) {
        // Quiet failure during background poll
      }
    }
  }

  Future<void> _manualCheckVerification() async {
    setState(() => _isChecking = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.reload();
        await user.getIdToken(true);
        if (user.emailVerified && mounted) {
          _pollTimer?.cancel();
          context.go('/pending-approval');
          return;
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error checking status: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    if (mounted) {
      setState(() => _isChecking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email has not been verified yet. Please check your inbox or spam folder.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (_resendCooldownSeconds > 0) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await user.sendEmailVerification();
        if (!mounted) return;
        setState(() => _resendCooldownSeconds = 30);
        _cooldownTimer?.cancel();
        _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            if (_resendCooldownSeconds > 1) {
              _resendCooldownSeconds--;
            } else {
              _resendCooldownSeconds = 0;
              timer.cancel();
            }
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification email resent. Please check your inbox.'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to resend: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () async {
              _pollTimer?.cancel();
              _cooldownTimer?.cancel();
              await ref.read(authControllerProvider.notifier).signOut();
              if (context.mounted) {
                context.go('/login');
              }
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 80,
                    color: Color(0xFF283593),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Verify Your Amrita Email',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to:\n${user?.email ?? 'your email'}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please click the link in your email to confirm your institutional affiliation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
                    label: const Text('I Have Verified My Email'),
                    onPressed: _isChecking ? null : _manualCheckVerification,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.send_outlined),
                    label: Text(
                      _resendCooldownSeconds > 0
                          ? 'Resend in ${_resendCooldownSeconds}s'
                          : 'Resend Verification Email',
                    ),
                    onPressed: _resendCooldownSeconds > 0 ? null : _resendVerificationEmail,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
