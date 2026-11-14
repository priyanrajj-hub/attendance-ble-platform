import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceSession {
  final String id;
  final String courseId;
  final String facultyId;
  final DateTime startedAt;
  final DateTime endsAt;
  final String status; // 'open' or 'closed'

  const AttendanceSession({
    required this.id,
    required this.courseId,
    required this.facultyId,
    required this.startedAt,
    required this.endsAt,
    required this.status,
  });

  bool get isOpen => status == 'open' && DateTime.now().isBefore(endsAt);
  bool get isClosed => !isOpen;

  int get remainingSeconds {
    if (!isOpen) return 0;
    final diff = endsAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  factory AttendanceSession.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawStart = data['startedAt'];
    final rawEnd = data['endsAt'];

    DateTime started = DateTime.now();
    DateTime ends = DateTime.now().add(const Duration(minutes: 15));

    if (rawStart is Timestamp) started = rawStart.toDate();
    if (rawEnd is Timestamp) ends = rawEnd.toDate();

    return AttendanceSession(
      id: doc.id,
      courseId: data['courseId'] as String? ?? '',
      facultyId: data['facultyId'] as String? ?? '',
      startedAt: started,
      endsAt: ends,
      status: data['status'] as String? ?? 'closed',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'courseId': courseId,
      'facultyId': facultyId,
      'startedAt': Timestamp.fromDate(startedAt),
      'endsAt': Timestamp.fromDate(endsAt),
      'status': status,
    };
  }
}

class LiveSessionCurrent {
  final String code;
  final String? prevCode;
  final DateTime rotatedAt;

  const LiveSessionCurrent({
    required this.code,
    this.prevCode,
    required this.rotatedAt,
  });

  factory LiveSessionCurrent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawRotated = data['rotatedAt'];
    DateTime rotated = DateTime.now();
    if (rawRotated is Timestamp) rotated = rawRotated.toDate();

    return LiveSessionCurrent(
      code: data['code'] as String? ?? '',
      prevCode: data['prevCode'] as String?,
      rotatedAt: rotated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      if (prevCode != null) 'prevCode': prevCode,
      'rotatedAt': Timestamp.fromDate(rotatedAt),
    };
  }
}
