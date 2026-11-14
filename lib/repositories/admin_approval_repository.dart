import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_role.dart';

enum ApprovalDecision {
  approve,
  reject,
  suspend,
}

class PendingUser {
  final String uid;
  final String email;
  final String fullName;
  final UserRole role;
  final String? rollNo;
  final DateTime createdAt;
  final String? deviceId;

  const PendingUser({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    this.rollNo,
    required this.createdAt,
    this.deviceId,
  });

  factory PendingUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final roleStr = data['role'] as String? ?? 'student';
    final role = roleStr == 'faculty'
        ? UserRole.faculty
        : roleStr == 'admin'
            ? UserRole.admin
            : UserRole.student;

    final dynamic rawCreated = data['createdAt'];
    DateTime created = DateTime.now();
    if (rawCreated is Timestamp) {
      created = rawCreated.toDate();
    }

    return PendingUser(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      fullName: data['name'] as String? ?? data['fullName'] as String? ?? 'Unnamed User',
      role: role,
      rollNo: data['rollNo'] as String?,
      createdAt: created,
      deviceId: data['deviceId'] as String?,
    );
  }
}

abstract class AdminApprovalRepository {
  Stream<List<PendingUser>> watchPendingUsers();

  Future<void> reviewUser({
    required String uid,
    required ApprovalDecision decision,
    String? reason,
  });

  Future<void> resetDevice({required String uid});
}

class FirestoreAdminApprovalRepository implements AdminApprovalRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FirestoreAdminApprovalRepository(this._firestore, this._auth);

  @override
  Stream<List<PendingUser>> watchPendingUsers() {
    return _firestore
        .collection('users')
        .where('status', isEqualTo: 'pending_verification')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(PendingUser.fromDoc).toList());
  }

  @override
  Future<void> reviewUser({
    required String uid,
    required ApprovalDecision decision,
    String? reason,
  }) async {
    final currentAdmin = _auth.currentUser;
    if (currentAdmin == null) {
      throw StateError('Admin must be authenticated to review users');
    }

    String statusStr;
    switch (decision) {
      case ApprovalDecision.approve:
        statusStr = 'verified';
        break;
      case ApprovalDecision.reject:
        statusStr = 'rejected';
        break;
      case ApprovalDecision.suspend:
        statusStr = 'suspended';
        break;
    }

    final updateData = <String, dynamic>{
      'status': statusStr,
      'verifiedBy': currentAdmin.uid,
      'verifiedAt': FieldValue.serverTimestamp(),
    };

    if (reason != null && reason.isNotEmpty) {
      updateData['rejectionReason'] = reason;
    }

    await _firestore.collection('users').doc(uid).update(updateData);
  }

  @override
  Future<void> resetDevice({required String uid}) async {
    final currentAdmin = _auth.currentUser;
    if (currentAdmin == null) {
      throw StateError('Admin must be authenticated to reset devices');
    }

    await _firestore.collection('users').doc(uid).update({
      'deviceId': FieldValue.delete(),
      'verifiedBy': currentAdmin.uid,
      'verifiedAt': FieldValue.serverTimestamp(),
    });
  }
}

final adminApprovalRepositoryProvider = Provider<AdminApprovalRepository>((ref) {
  return FirestoreAdminApprovalRepository(
    FirebaseFirestore.instance,
    FirebaseAuth.instance,
  );
});
