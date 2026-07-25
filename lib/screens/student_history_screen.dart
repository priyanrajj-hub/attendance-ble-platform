import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/session_service.dart';

/// Student attendance history screen — shows attendance records
/// across all sessions with per-subject percentage.
class StudentHistoryScreen extends StatefulWidget {
  const StudentHistoryScreen({super.key});

  @override
  State<StudentHistoryScreen> createState() => _StudentHistoryScreenState();
}

class _StudentHistoryScreenState extends State<StudentHistoryScreen> {
  final _sessionService = SessionService();
  List<Map<String, dynamic>> _history = [];
  Map<String, double> _percentages = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final history = await _sessionService.studentHistory(user.uid);

    // Calculate per-subject percentages
    final subjectMap = <String, List<String>>{};
    for (final entry in history) {
      final session = entry['session'];
      final status = entry['status'] as String;
      final subject = session.subjectName as String;
      subjectMap.putIfAbsent(subject, () => []).add(status);
    }

    final percentages = <String, double>{};
    for (final entry in subjectMap.entries) {
      final total = entry.value.length;
      final present =
          entry.value.where((s) => s == 'present' || s == 'od').length;
      percentages[entry.key] = total > 0 ? (present / total) * 100 : 0;
    }

    if (mounted) {
      setState(() {
        _history = history;
        _percentages = percentages;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Attendance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: Column(
        children: [
          // Subject-wise percentage cards
          if (_percentages.isNotEmpty) ...[
            SizedBox(
              height: 130,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(16),
                children: _percentages.entries.map((entry) {
                  final percent = entry.value;
                  Color percentColor;
                  if (percent >= 75) {
                    percentColor = Colors.green;
                  } else if (percent >= 50) {
                    percentColor = Colors.orange;
                  } else {
                    percentColor = Colors.red;
                  }

                  return Container(
                    width: 160,
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: percentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: percentColor.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Text(
                          '${percent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: percentColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // History list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Recent Sessions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${_history.length} total',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: _history.isEmpty
                ? const Center(child: Text('No attendance records yet.'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      final entry = _history[index];
                      final session = entry['session'];
                      final status = entry['status'] as String;

                      Color statusColor;
                      IconData statusIcon;
                      switch (status) {
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
                            backgroundColor:
                                statusColor.withValues(alpha: 0.15),
                            child: Icon(statusIcon, color: statusColor),
                          ),
                          title: Text(
                            session.subjectName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${session.classId} · ${_formatDate(session.startTime)}',
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
