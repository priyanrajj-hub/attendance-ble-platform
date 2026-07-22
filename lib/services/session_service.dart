import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';
import 'token_service.dart';

/// Manages attendance sessions and records in Firestore.
class SessionService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ─── Session management ───────────────────────────────────────────

  /// Faculty creates a new attendance session (5-10 min window).
  Future<AttendanceSession> createSession({
    required String classId,
    required String subjectName,
    int durationMinutes = 5,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final now = DateTime.now();
    final secret = TokenService.generateSessionSecret();

    final docRef = _firestore.collection('sessions').doc();

    final session = AttendanceSession(
      sessionId: docRef.id,
      classId: classId,
      subjectName: subjectName,
      facultyId: user.uid,
      startTime: now,
      endTime: now.add(Duration(minutes: durationMinutes)),
      status: 'active',
      hmacSecret: secret,
    );

    // Save metadata without hmacSecret in public doc to prevent student reading it
    final sessionMap = session.toFirestore();
    sessionMap.remove('hmacSecret');
    await docRef.set(sessionMap);

    // Save hmacSecret in private subcollection details document
    await docRef.collection('private').doc('details').set({
      'hmacSecret': secret,
      'facultyId': user.uid,
    });

    return session;
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

  /// Mark a student as present (called after HMAC verification + RSSI check).
  Future<void> markPresent({
    required String sessionId,
    required String studentUid,
    required String hmacToken,
    required int rssi,
    required int scanCount,
  }) async {
    // Call the Cloud Function markAttendance (verifies HMAC, RSSI, scanCount on the server-side)
    await FirebaseFunctions.instance.httpsCallable('markAttendance').call({
      'sessionId': sessionId,
      'studentUid': studentUid,
      'hmacToken': hmacToken,
      'rssi': rssi,
      'scanCount': scanCount,
    });
  }


  /// Edit an attendance record (faculty: present↔absent, mentor: can set OD).
  /// Edit an attendance record via Cloud Function (restricted by Faculty/Mentor roles).
  Future<void> editAttendance({
    required String sessionId,
    required String studentUid,
    required String newStatus,
  }) async {
    // Call the Cloud Function editAttendance
    await FirebaseFunctions.instance.httpsCallable('editAttendance').call({
      'sessionId': sessionId,
      'studentUid': studentUid,
      'newStatus': newStatus,
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

      history.add({
        'session': session,
        'status': attendanceDoc.exists
            ? attendanceDoc.data()?['status'] ?? 'absent'
            : 'absent',
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
