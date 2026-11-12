import 'dart:async';
import '../models/user_role.dart';
import 'admin_approval_repository.dart';

/// In-memory fake repository for Gate 1 UI testing.
/// Contains ZERO direct client Firestore writes.
class FakeAdminApprovalRepository implements AdminApprovalRepository {
  final _controller = StreamController<List<PendingUser>>.broadcast();

  final List<PendingUser> _pendingUsers = [
    PendingUser(
      uid: 'pending_stu_001',
      email: 'aarav.p@ch.students.amrita.edu',
      fullName: 'Aarav Patel',
      role: UserRole.student,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    PendingUser(
      uid: 'pending_stu_002',
      email: 'diya.s@ch.students.amrita.edu',
      fullName: 'Diya Sharma',
      role: UserRole.student,
      createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    PendingUser(
      uid: 'pending_fac_001',
      email: 'k.nair@ch.amrita.edu',
      fullName: 'Dr. K. Nair',
      role: UserRole.faculty,
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
  ];

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_pendingUsers));
    }
  }

  @override
  Stream<List<PendingUser>> watchPendingUsers() {
    return Stream<List<PendingUser>>.multi((controller) {
      controller.add(List.unmodifiable(_pendingUsers));
      final subscription = _controller.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = () {
        subscription.cancel();
      };
    });
  }

  @override
  Future<void> reviewUser({
    required String uid,
    required ApprovalDecision decision,
    String? reason,
  }) async {
    // Simulates server-side processing without any direct Firestore client write
    _pendingUsers.removeWhere((u) => u.uid == uid);
    _emit();
  }

  void dispose() {
    _controller.close();
  }
}
