import 'package:cloud_firestore/cloud_firestore.dart';

class Enrollment {
  final String id; // courseId_studentUid
  final String courseId;
  final String studentUid;
  final String studentName;
  final String rollNo;
  final DateTime enrolledAt;

  const Enrollment({
    required this.id,
    required this.courseId,
    required this.studentUid,
    required this.studentName,
    required this.rollNo,
    required this.enrolledAt,
  });

  factory Enrollment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawDate = data['enrolledAt'];
    DateTime enrolled = DateTime.now();
    if (rawDate is Timestamp) {
      enrolled = rawDate.toDate();
    }

    return Enrollment(
      id: doc.id,
      courseId: data['courseId'] as String? ?? '',
      studentUid: data['studentUid'] as String? ?? '',
      studentName: data['studentName'] as String? ?? '',
      rollNo: data['rollNo'] as String? ?? '',
      enrolledAt: enrolled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'courseId': courseId,
      'studentUid': studentUid,
      'studentName': studentName,
      'rollNo': rollNo,
      'enrolledAt': Timestamp.fromDate(enrolledAt),
    };
  }
}
