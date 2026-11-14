import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../services/attendance_api_service.dart';

class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends ConsumerState<AttendanceHistoryScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(attendanceApiServiceProvider);
      final list = await api.getMyAttendanceHistory();
      if (mounted) {
        setState(() {
          _records = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load attendance records: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _promptDispute(Map<String, dynamic> record) async {
    final sessionId = record['session_id'] as String?;
    final courseCode = record['course_code'] as String? ?? 'Course';
    if (sessionId == null) return;

    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Report Issue: $courseCode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Submit an attendance correction request or grievance for this class session.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (minimum 5 characters)',
                hintText: 'e.g. Present in room, phone Bluetooth packet missed.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().length >= 5) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Submit Grievance'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final api = ref.read(attendanceApiServiceProvider);
      final ok = await api.submitDispute(
        sessionId: sessionId,
        reason: reasonController.text.trim(),
      );

      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dispute submitted successfully for faculty review.'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to submit dispute. A pending request may already exist.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final presentCount = _records.where((r) => r['status'] == 'present' || r['status'] == 'present_override').length;
    final verifiedSignatureCount = _records.where((r) => r['signature_verified'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(_errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadHistory, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              label: 'Sessions Marked',
                              value: '$presentCount / ${_records.length}',
                              color: Colors.indigo,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              label: 'Cryptographically Signed',
                              value: '$verifiedSignatureCount',
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Authoritative Verified Attendance Log',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      if (_records.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_toggle_off, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text(
                                  'No attendance records found yet',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'When your faculty broadcasts attendance in class, check in via BLE to see verified entries here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ..._records.map((r) {
                          final isBle = r['method'] == 'ble_signed_nonce';
                          final courseCode = r['course_code'] as String? ?? 'COURSE';
                          final courseName = r['course_name'] as String? ?? '';
                          final roomLabel = r['room_label'] as String? ?? 'Classroom';
                          final verifiedAtStr = r['verified_at'] as String?;
                          final verifiedAt = verifiedAtStr != null
                              ? DateTime.tryParse(verifiedAtStr)?.toLocal() ?? DateTime.now()
                              : DateTime.now();
                          final formattedDate = DateFormat('MMM dd, yyyy • hh:mm a').format(verifiedAt);
                          final rssi = r['rssi_observed'];
                          final signatureVerified = r['signature_verified'] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isBle ? Colors.indigo.shade50 : Colors.amber.shade50,
                                        child: Icon(
                                          isBle ? Icons.bluetooth_connected : Icons.edit_note,
                                          color: isBle ? const Color(0xFF283593) : Colors.amber.shade900,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$courseCode - $courseName',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$roomLabel • $formattedDate',
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                            ),
                                            if (isBle && rssi != null)
                                              Text(
                                                'Observed RSSI: $rssi dBm ${signatureVerified ? "• Hardware Signed" : ""}',
                                                style: TextStyle(color: Colors.indigo.shade700, fontSize: 11),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green.shade200),
                                        ),
                                        child: const Text(
                                          'PRESENT',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.help_outline, size: 14),
                                      label: const Text('Report Issue / Grievance', style: TextStyle(fontSize: 11)),
                                      onPressed: () => _promptDispute(r),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final MaterialColor color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color.shade700,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
