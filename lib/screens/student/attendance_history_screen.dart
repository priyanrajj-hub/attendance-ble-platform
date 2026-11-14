import 'package:flutter/material.dart';

class AttendanceHistoryScreen extends StatelessWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> records = [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  label: 'Classes Attended',
                  value: '${records.length}',
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  label: 'Attendance Rate',
                  value: records.isEmpty ? 'No data' : '100%',
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Recent Session Log',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...records.map((r) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: r['status'] == 'Present'
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    child: Icon(
                      r['status'] == 'Present' ? Icons.check : Icons.access_time,
                      color: r['status'] == 'Present' ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(
                    r['course']!,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Text('${r['date']} • ${r['room']}\nVerified via ${r['mode']}'),
                  trailing: Chip(
                    label: Text(r['status']!),
                    backgroundColor: r['status'] == 'Present'
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    labelStyle: TextStyle(
                      color: r['status'] == 'Present' ? Colors.green.shade900 : Colors.orange.shade900,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final MaterialColor color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
