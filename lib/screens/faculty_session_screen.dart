import 'dart:async';
import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../models/attendance_session.dart';
import 'faculty_scan_screen.dart';
import 'session_history_screen.dart';

/// Faculty creates / manages attendance sessions from this screen.
///
/// Flow: select class + subject → set duration → "Start Session" →
/// a countdown shows remaining time → navigate to scan screen to
/// detect students → "End Session" stops early.
class FacultySessionScreen extends StatefulWidget {
  const FacultySessionScreen({super.key});

  @override
  State<FacultySessionScreen> createState() => _FacultySessionScreenState();
}

class _FacultySessionScreenState extends State<FacultySessionScreen> {
  final _sessionService = SessionService();
  final _classCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();

  int _durationMinutes = 5;
  AttendanceSession? _activeSession;
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _classCtrl.dispose();
    _subjectCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    final session = await _sessionService.getActiveSession();
    if (session != null && mounted) {
      setState(() => _activeSession = session);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = _activeSession?.remainingSeconds ?? 0;
      if (remaining <= 0) {
        timer.cancel();
        setState(() => _activeSession = null);
        return;
      }
      setState(() => _remainingSeconds = remaining);
    });
  }

  Future<void> _startSession() async {
    final classId = _classCtrl.text.trim();
    final subject = _subjectCtrl.text.trim();

    if (classId.isEmpty || subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in class ID and subject.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final session = await _sessionService.createSession(
        classId: classId,
        subjectName: subject,
        durationMinutes: _durationMinutes,
      );
      setState(() {
        _activeSession = session;
        _loading = false;
      });
      _startCountdown();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start session: $e')),
        );
      }
    }
  }

  Future<void> _endSession() async {
    if (_activeSession == null) return;
    setState(() => _loading = true);
    try {
      await _sessionService.closeSession(_activeSession!.sessionId);
      _countdownTimer?.cancel();
      setState(() {
        _activeSession = null;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasActive = _activeSession != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Session History',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SessionHistoryScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            tooltip: 'Admin Panel',
            onPressed: () => Navigator.pushNamed(context, '/admin'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: hasActive
            ? _buildActiveSession(colorScheme)
            : _buildNewSession(colorScheme),
      ),
    );
  }

  Widget _buildActiveSession(ColorScheme colorScheme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Timer display
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(Icons.timer, size: 48, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Session Active',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatTime(_remainingSeconds),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_activeSession!.subjectName} · ${_activeSession!.classId}',
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Scan button
        FilledButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FacultyScanScreen(session: _activeSession!),
              ),
            );
          },
          icon: const Icon(Icons.bluetooth_searching),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('Scan for Students', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 12),

        // End session
        OutlinedButton.icon(
          onPressed: _loading ? null : _endSession,
          icon: const Icon(Icons.stop_circle_outlined),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              _loading ? 'Ending...' : 'End Session',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
        ),
      ],
    );
  }

  Widget _buildNewSession(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.play_circle_outline, size: 64, color: colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Start Attendance Session',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 32),

        TextField(
          controller: _classCtrl,
          decoration: const InputDecoration(
            labelText: 'Class ID',
            hintText: 'e.g., CSE-3A',
            prefixIcon: Icon(Icons.class_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _subjectCtrl,
          decoration: const InputDecoration(
            labelText: 'Subject',
            hintText: 'e.g., Data Structures',
            prefixIcon: Icon(Icons.subject),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Duration selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              const Text('Duration: '),
              const Spacer(),
              DropdownButton<int>(
                value: _durationMinutes,
                underline: const SizedBox(),
                items: [3, 5, 7, 10]
                    .map((m) =>
                        DropdownMenuItem(value: m, child: Text('$m minutes')))
                    .toList(),
                onChanged: (v) => setState(() => _durationMinutes = v ?? 5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        FilledButton(
          onPressed: _loading ? null : _startSession,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Start Session', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
}
