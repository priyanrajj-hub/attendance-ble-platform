import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_role.dart';
import 'fake_admin_approval_repository.dart';

enum ApprovalDecision {
  approve,
  reject,
}

class PendingUser {
  final String uid;
  final String email;
  final String fullName;
  final UserRole role;
  final DateTime createdAt;

  const PendingUser({
    required this.uid,
    required this.email,
    required this.fullName,
    required this.role,
    required this.createdAt,
  });
}

/// Abstract contract for Admin user approval.
/// Prevents client-side direct writes to Firestore status/role/verifiedBy fields.
///
/// In Gate 1, backed by FakeAdminApprovalRepository (in-memory).
/// In Gate 2, backed by HttpAdminApprovalRepository (calling FastAPI server endpoint).
abstract class AdminApprovalRepository {
  Stream<List<PendingUser>> watchPendingUsers();

  Future<void> reviewUser({
    required String uid,
    required ApprovalDecision decision,
    String? reason,
  });
}

final adminApprovalRepositoryProvider = Provider<AdminApprovalRepository>((ref) {
  // In Gate 1, defaults to FakeAdminApprovalRepository for safe UI review
  return FakeAdminApprovalRepository();
});
