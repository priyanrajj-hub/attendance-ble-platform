import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/proximity_provider.dart';

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  bool _isCheckingIn = false;
  CheckInPayload? _lastProof;
  String? _proximityError;

  Future<void> _startProximityFlow() async {
    setState(() {
      _isCheckingIn = true;
      _lastProof = null;
      _proximityError = null;
    });

    try {
      final prox = ref.read(proximityProvider);
      await prox.startSession('SESSION_CSE450_TODAY', role: UserRole.student);
    } catch (e) {
      setState(() {
        _isCheckingIn = false;
        _proximityError = 'Hardware proximity service not yet initialized on this device: $e';
      });
    }
  }

  Future<void> _completeCheckIn() async {
    try {
      final prox = ref.read(proximityProvider);
      final proof = await prox.captureProximityProof();
      setState(() {
        _lastProof = proof;
        _isCheckingIn = false;
      });

      if (mounted && proof != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Proximity proof generated! Session: ${proof.sessionId}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _proximityError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;

    ProximityState? proxState;
    try {
      proxState = ref.watch(proximityProvider).currentState;
    } catch (_) {
      // In prod builds without a bound BLE provider, currentState safely defaults
      proxState = ProximityState.initial();
    }

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
            // Student Welcome Header
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
            const SizedBox(height: 16),

            // Active Class Detection Card
            Text(
              'Active Classroom Session',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.class_outlined, color: Color(0xFF283593)),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '19CSE450: Mobile Computing',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              Text(
                                'Room 204 • Dr. R. Subramanian',
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ACTIVE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),

                    if (_proximityError != null) ...[
                      Text(
                        _proximityError!,
                        style: const TextStyle(color: Colors.orange, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Proximity State Visualization
                    if (proxState.status == ProximityStatus.scanning) ...[
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Scanning for classroom BLE signal...',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ] else if (proxState.status == ProximityStatus.deviceDetected) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.signal_cellular_alt, color: Colors.green),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Faculty Beacon Verified in Range',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                  Text(
                                    'RSSI: ${proxState.rssiDbm} dBm (Line of Sight)',
                                    style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.verified_user_outlined),
                        label: const Text('Confirm & Submit Attendance'),
                        onPressed: _completeCheckIn,
                      ),
                    ] else if (_lastProof != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF283593)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Attendance Proof Recorded\nNonce: ${_lastProof!.nonce}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF283593),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.sensors),
                        label: const Text('Scan & Check In'),
                        onPressed: _isCheckingIn ? null : _startProximityFlow,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Quick Stats Card
            Card(
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined, color: Color(0xFF283593)),
                title: const Text('My Attendance Rate'),
                subtitle: const Text('Semester Overall: 94.2% (Requirement: 75%)'),
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
