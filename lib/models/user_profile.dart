import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_role.dart';

enum AccountStatus {
  pendingVerification,
  verified,
  rejected,
  suspended;

  String get value {
    switch (this) {
      case AccountStatus.pendingVerification:
        return 'pending_verification';
      case AccountStatus.verified:
        return 'verified';
      case AccountStatus.rejected:
        return 'rejected';
      case AccountStatus.suspended:
        return 'suspended';
    }
  }

  static AccountStatus fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'verified':
        return AccountStatus.verified;
      case 'rejected':
        return AccountStatus.rejected;
      case 'suspended':
        return AccountStatus.suspended;
      case 'pending_verification':
      default:
        return AccountStatus.pendingVerification;
    }
  }
}

class UserProfile {
  final String uid;
  final String email;
  final String fullName;
  final UserRole role;
  final AccountStatus status;
  final String? rollNo;
  final String? deviceId;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? rejectionReason;
  final DateTime createdAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.rollNo,
    this.deviceId,
    this.verifiedBy,
    this.verifiedAt,
    this.rejectionReason,
    required this.createdAt,
  });

  bool get hasValidInstitutionalDomain {
    return email.toLowerCase().endsWith(role.expectedDomain);
  }

  bool get isVerified => status == AccountStatus.verified;
  bool get isPending => status == AccountStatus.pendingVerification;
  bool get isRejected => status == AccountStatus.rejected;
  bool get isSuspended => status == AccountStatus.suspended;

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    final roleStr = data['role'] as String?;
    final statusStr = data['status'] as String?;

    DateTime parseDt(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      fullName: data['name'] as String? ?? data['fullName'] as String? ?? 'Unknown User',
      role: UserRole.fromString(roleStr),
      status: AccountStatus.fromString(statusStr),
      rollNo: data['rollNo'] as String?,
      deviceId: data['deviceId'] as String?,
      verifiedBy: data['verifiedBy'] as String?,
      verifiedAt: data['verifiedAt'] != null ? parseDt(data['verifiedAt']) : null,
      rejectionReason: data['rejectionReason'] as String?,
      createdAt: parseDt(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': fullName,
      'email': email,
      'role': role.firestoreKey,
      'status': status.value,
      if (rollNo != null) 'rollNo': rollNo,
      if (deviceId != null) 'deviceId': deviceId,
      if (verifiedBy != null) 'verifiedBy': verifiedBy,
      if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
      if (rejectionReason != null) 'rejectionReason': rejectionReason,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
