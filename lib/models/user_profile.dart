import 'user_role.dart';

enum AccountStatus {
  pendingVerification,
  verified,
  suspended;

  String get value {
    switch (this) {
      case AccountStatus.pendingVerification:
        return 'pending_verification';
      case AccountStatus.verified:
        return 'verified';
      case AccountStatus.suspended:
        return 'suspended';
    }
  }

  static AccountStatus fromString(String? val) {
    switch (val?.toLowerCase().trim()) {
      case 'verified':
        return AccountStatus.verified;
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
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  const UserProfile({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    required this.status,
    this.verifiedBy,
    this.verifiedAt,
    required this.createdAt,
  });

  /// Validates institutional domain binding strictly
  bool get hasValidInstitutionalDomain {
    return email.toLowerCase().endsWith(role.expectedDomain);
  }

  bool get isVerified => status == AccountStatus.verified;

  factory UserProfile.fromMap(Map<String, dynamic> data, String uid) {
    final roleStr = data['role'] as String? ?? 'student';
    final statusStr = data['status'] as String? ?? 'pending_verification';

    DateTime parseDt(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      if (val is String) {
        return DateTime.tryParse(val) ?? DateTime.now();
      }
      if (val.runtimeType.toString().contains('Timestamp')) {
        try {
          return (val as dynamic).toDate() as DateTime;
        } catch (_) {}
      }
      return DateTime.now();
    }

    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      fullName: data['fullName'] as String? ?? (data['name'] as String? ?? 'Unknown User'),
      role: UserRole.fromString(roleStr),
      status: AccountStatus.fromString(statusStr),
      verifiedBy: data['verifiedBy'] as String?,
      verifiedAt: data['verifiedAt'] != null ? parseDt(data['verifiedAt']) : null,
      createdAt: parseDt(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'fullName': fullName,
      'role': role.name,
      'status': status.value,
      'verifiedBy': verifiedBy,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
