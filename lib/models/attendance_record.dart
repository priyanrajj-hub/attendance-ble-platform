import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceRecord {
  final String studentUid;
  final DateTime markedAt;
  final String method; // 'ble' or 'manual'
  final String? code;
  final int? rssi;
  final String? deviceId;
  final String? markedBy;
  final String? reason;

  const AttendanceRecord({
    required this.studentUid,
    required this.markedAt,
    required this.method,
    this.code,
    this.rssi,
    this.deviceId,
    this.markedBy,
    this.reason,
  });

  bool get isBle => method == 'ble';
  bool get isManual => method == 'manual';

  factory AttendanceRecord.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawMarked = data['markedAt'];
    DateTime marked = DateTime.now();
    if (rawMarked is Timestamp) marked = rawMarked.toDate();

    return AttendanceRecord(
      studentUid: data['studentUid'] as String? ?? doc.id,
      markedAt: marked,
      method: data['method'] as String? ?? 'ble',
      code: data['code'] as String?,
      rssi: data['rssi'] as int?,
      deviceId: data['deviceId'] as String?,
      markedBy: data['markedBy'] as String?,
      reason: data['reason'] as String?,
    );
  }

  Map<String, dynamic> toBleMap() {
    return {
      'studentUid': studentUid,
      'markedAt': Timestamp.fromDate(markedAt),
      'method': 'ble',
      'code': code,
      'rssi': rssi,
      'deviceId': deviceId,
    };
  }

  Map<String, dynamic> toManualMap() {
    return {
      'studentUid': studentUid,
      'markedAt': Timestamp.fromDate(markedAt),
      'method': 'manual',
      'markedBy': markedBy,
      'reason': reason,
    };
  }
}
