import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';
import 'token_service.dart';

/// Manages attendance sessions and records in Firestore.
class SessionService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ─── Session management ───────────────────────────────────────────

  /// Faculty creates a new attendance session (5-10 min window) via server-side Cloud Function.
  Future<AttendanceSession> createSession({
    required String classId,
    required String subjectName,
    int durationMinutes = 5,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    // Generate unique ID and secret locally
    final sessionRef = _firestore.collection('sessions').doc();
    final sessionId = sessionRef.id;
    final hmacSecret = TokenService.generateSessionSecret();

    final now = DateTime.now();
    final endTime = now.add(Duration(minutes: durationMinutes));

    // Write public session data
    await sessionRef.set({
      'classId': classId,
      'subjectName': subjectName,
      'facultyId': user.uid,
      'startTime': Timestamp.fromDate(now),
      'endTime': Timestamp.fromDate(endTime),
      'status': 'active',
    });

    // Write private hmacSecret
    await sessionRef.collection('private').doc('details').set({
      'hmacSecret': hmacSecret,
      'facultyId': user.uid,
    });

    // Fetch the public session details
    final sessionDoc =
        await _firestore.collection('sessions').doc(sessionId).get();
    final data = sessionDoc.data() ?? {};

    return AttendanceSession(
      sessionId: sessionId,
      classId: data['classId'] ?? classId,
      subjectName: data['subjectName'] ?? subjectName,
      facultyId: data['facultyId'] ?? user.uid,
      startTime: data['startTime'] != null
          ? (data['startTime'] as Timestamp).toDate()
          : DateTime.now(),
      endTime: data['endTime'] != null
          ? (data['endTime'] as Timestamp).toDate()
          : DateTime.now().add(Duration(minutes: durationMinutes)),
      status: data['status'] ?? 'active',
      hmacSecret: hmacSecret,
    );
  }

  /// Close a session manually (faculty stops early).
  Future<void> closeSession(String sessionId) async {
    await _firestore.collection('sessions').doc(sessionId).update({
      'status': 'closed',
      'endTime': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Get the current active session for a faculty member.
  Future<AttendanceSession?> getActiveSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final query = await _firestore
        .collection('sessions')
        .where('facultyId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'active')
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final sessionId = doc.id;

    // Fetch the hmacSecret from the private details subcollection (faculty has read permission)
    final secretDoc = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('private')
        .doc('details')
        .get();
    final hmacSecret = secretDoc.data()?['hmacSecret'] as String? ?? '';

    final data = doc.data();
    final session = AttendanceSession(
      sessionId: sessionId,
      classId: data['classId'] ?? '',
      subjectName: data['subjectName'] ?? '',
      facultyId: data['facultyId'] ?? '',
      startTime: (data['startTime'] as Timestamp).toDate(),
      endTime: (data['endTime'] as Timestamp).toDate(),
      status: data['status'] ?? 'closed',
      hmacSecret: hmacSecret,
    );

    // Auto-expire if past endTime
    if (DateTime.now().isAfter(session.endTime)) {
      await _firestore
          .collection('sessions')
          .doc(session.sessionId)
          .update({'status': 'expired'});
      return null;
    }
    return session;
  }

  /// Get any active session (for students to find the current window).
  Future<AttendanceSession?> findActiveSession() async {
    final query = await _firestore
        .collection('sessions')
        .where('status', isEqualTo: 'active')
        .orderBy('startTime', descending: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final session = AttendanceSession.fromFirestore(query.docs.first);
    if (DateTime.now().isAfter(session.endTime)) {
      await _firestore
          .collection('sessions')
          .doc(session.sessionId)
          .update({'status': 'expired'});
      return null;
    }
    return session;
  }

  /// Stream of sessions for the faculty (history).
  Stream<List<AttendanceSession>> facultySessions() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _firestore
        .collection('sessions')
        .where('facultyId', isEqualTo: user.uid)
        .orderBy('startTime', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AttendanceSession.fromFirestore(d)).toList());
  }

  // ─── Attendance records ───────────────────────────────────────────

  Future<void> markPresent({
    required String sessionId,
    required String studentUid,
    required String hmacToken,
    required int rssi,
    required int scanCount,
  }) async {
    // Fetch hmacSecret from the private details subcollection (faculty has read permission)
    final secretDoc = await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('private')
        .doc('details')
        .get();

    final hmacSecret = secretDoc.data()?['hmacSecret'] as String? ?? '';

    // Verify HMAC client-side
    final isValid =
        TokenService.verifyTokenFragment(sessionId, hmacSecret, hmacToken);
    if (!isValid) {
      throw Exception('Invalid HMAC token for student: $studentUid');
    }

    // Direct Firestore write for attendance
    await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('attendance')
        .doc(studentUid)
        .set({
      'status': 'present',
      'rssi': rssi,
      'scanCount': scanCount,
      'markedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Edit an attendance record via direct Firestore write (restricted by Faculty/Admin roles).
  Future<void> editAttendance({
    required String sessionId,
    required String studentUid,
    required String newStatus,
  }) async {
    // Direct Firestore update for attendance
    await _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('attendance')
        .doc(studentUid)
        .update({
      'status': newStatus,
    });
  }

  /// Get attendance records for a session.
  Stream<List<AttendanceRecord>> sessionAttendance(String sessionId) {
    return _firestore
        .collection('sessions')
        .doc(sessionId)
        .collection('attendance')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => AttendanceRecord.fromFirestore(d)).toList());
  }

  /// Get attendance history for a specific student across all sessions.
  Future<List<Map<String, dynamic>>> studentHistory(String studentUid) async {
    final sessions = await _firestore
        .collection('sessions')
        .orderBy('startTime', descending: true)
        .get();

    final history = <Map<String, dynamic>>[];

    for (final sessionDoc in sessions.docs) {
      final session = AttendanceSession.fromFirestore(sessionDoc);
      final attendanceDoc = await _firestore
          .collection('sessions')
          .doc(session.sessionId)
          .collection('attendance')
          .doc(studentUid)
          .get();

      final docData = attendanceDoc.data();
      final status = (docData != null)
          ? (docData['status'] as String? ?? 'absent')
          : 'absent';

      history.add({
        'session': session,
        'status': status,
        'record': attendanceDoc.exists
            ? AttendanceRecord.fromFirestore(attendanceDoc)
            : null,
      });
    }
    return history;
  }

  /// Calculate attendance percentage for a student in a specific subject.
  Future<double> attendancePercentage(
      String studentUid, String subjectName) async {
    final sessions = await _firestore
        .collection('sessions')
        .where('subjectName', isEqualTo: subjectName)
        .get();

    if (sessions.docs.isEmpty) return 0.0;

    int totalSessions = sessions.docs.length;
    int presentCount = 0;

    for (final sessionDoc in sessions.docs) {
      final attendanceDoc = await _firestore
          .collection('sessions')
          .doc(sessionDoc.id)
          .collection('attendance')
          .doc(studentUid)
          .get();

      if (attendanceDoc.exists) {
        final status = attendanceDoc.data()?['status'];
        if (status == 'present' || status == 'od') {
          presentCount++;
        }
      }
    }
    return (presentCount / totalSessions) * 100;
  }
}
