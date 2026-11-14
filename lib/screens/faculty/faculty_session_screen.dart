import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_role.dart';
import '../../providers/proximity_provider.dart';

class FacultySessionScreen extends ConsumerStatefulWidget {
  final String courseId;
  final String courseName;

  const FacultySessionScreen({
    super.key,
    required this.courseId,
    required this.courseName,
  });

  @override
  ConsumerState<FacultySessionScreen> createState() => _FacultySessionScreenState();
}

class _FacultySessionScreenState extends ConsumerState<FacultySessionScreen> {
  int _secondsRemaining = 900; // 15-minute active window
  Timer? _timer;
  bool _isSessionActive = false;

  final List<Map<String, dynamic>> _roster = [];

  @override
  void initState() {
    super.initState();
    _startLiveSession();
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      ref.read(proximityProvider).stopSession();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _startLiveSession() async {
    setState(() => _isSessionActive = true);
    try {
      final prox = ref.read(proximityProvider);
      await prox.startSession('SESSION_${widget.courseId}', role: UserRole.faculty);
    } catch (_) {
      // In prod builds without a bound BLE provider, session starts in offline display mode
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _endSession();
      }
    });
  }

  Future<void> _endSession() async {
    _timer?.cancel();
    try {
      await ref.read(proximityProvider).stopSession();
    } catch (_) {}
    setState(() => _isSessionActive = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session closed. Attendance finalized.')),
      );
    }
  }

  void _toggleManualOverride(int index) {
    setState(() {
      final current = _roster[index]['checkedIn'] as bool;
      _roster[index]['checkedIn'] = !current;
      _roster[index]['time'] = !current ? 'Manual Override' : null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Manual attendance override applied for ${_roster[index]['name']}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkedInCount = _roster.where((s) => s['checkedIn'] == true).length;
    final minutes = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_secondsRemaining % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.courseName),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/faculty'),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: _isSessionActive ? Colors.green.shade50 : Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _isSessionActive ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isSessionActive ? 'BROADCASTING BEACON' : 'SESSION CLOSED',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: _isSessionActive ? Colors.green.shade900 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attendance Window: $minutes:$seconds remaining',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSessionActive ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSessionActive ? _endSession : _startLiveSession,
                  child: Text(_isSessionActive ? 'Close Window' : 'Reopen'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Live Class Roster (${_roster.length} Enrolled)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Chip(
                  label: Text('$checkedInCount / ${_roster.length} Present'),
                  backgroundColor: Colors.indigo.shade50,
                  labelStyle: TextStyle(
                    color: Colors.indigo.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _roster.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final student = _roster[index];
                final isPresent = student['checkedIn'] as bool;

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPresent ? Colors.green.shade100 : Colors.grey.shade200,
                    child: Icon(
                      isPresent ? Icons.check : Icons.person_outline,
                      color: isPresent ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    student['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${student['roll']} • ${student['time'] ?? 'Pending Check-in'}',
                    style: TextStyle(
                      color: isPresent ? Colors.green.shade800 : Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(
                      isPresent ? Icons.edit : Icons.add_circle_outline,
                      color: isPresent ? Colors.grey : const Color(0xFF283593),
                    ),
                    tooltip: 'Manual Attendance Override',
                    onPressed: () => _toggleManualOverride(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
