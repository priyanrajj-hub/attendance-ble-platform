import 'package:flutter/material.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';
import '../services/session_service.dart';

/// Session history screen — shows all past sessions and their
/// attendance records. Faculty and mentor can edit status here.
class SessionHistoryScreen extends StatelessWidget {
  const SessionHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionService = SessionService();

    return Scaffold(
      appBar: AppBar(title: const Text('Session History')),
      body: StreamBuilder<List<AttendanceSession>>(
        stream: sessionService.facultySessions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return const Center(child: Text('No sessions yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final isActive = session.isActive;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive
                        ? Colors.green.withValues(alpha: 0.15)
                        : Colors.grey.withValues(alpha: 0.15),
                    child: Icon(
                      isActive ? Icons.play_circle : Icons.check_circle,
                      color: isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  title: Text(
                    session.subjectName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${session.classId} · ${_formatDateTime(session.startTime)} · ${session.status}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceListScreen(session: session),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Attendance list for a specific session — shows all students
/// with their status. Faculty/mentor can edit status (present/absent/OD).
class AttendanceListScreen extends StatelessWidget {
  final AttendanceSession session;

  const AttendanceListScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final sessionService = SessionService();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(session.subjectName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${session.classId} · ${_formatDateTime(session.startTime)}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<AttendanceRecord>>(
        stream: sessionService.sessionAttendance(session.sessionId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data ?? [];
          if (records.isEmpty) {
            return const Center(child: Text('No attendance records yet.'));
          }

          // Sort by roll number
          records.sort((a, b) => a.rollNo.compareTo(b.rollNo));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];

              Color statusColor;
              IconData statusIcon;
              switch (record.status) {
                case 'present':
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                  break;
                case 'od':
                  statusColor = Colors.blue;
                  statusIcon = Icons.work_outline;
                  break;
                default:
                  statusColor = Colors.red;
                  statusIcon = Icons.cancel;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.15),
                    child: Icon(statusIcon, color: statusColor),
                  ),
                  title: Text(
                    record.studentName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${record.rollNo} · ${record.rssi} dBm · ${record.scanCount} scans',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (newStatus) {
                      sessionService.editAttendance(
                        sessionId: session.sessionId,
                        studentUid: record.studentId,
                        newStatus: newStatus,
                      );
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'present', child: Text('Mark Present')),
                      const PopupMenuItem(
                          value: 'absent', child: Text('Mark Absent')),
                      const PopupMenuItem(
                          value: 'od', child: Text('Mark OD (Mentor only)')),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        record.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
