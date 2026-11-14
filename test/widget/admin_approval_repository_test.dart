import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/repositories/admin_approval_repository.dart';
import 'package:amrita_ble_attendance/repositories/fake_admin_approval_repository.dart';

void main() {
  group('AdminApprovalRepository Gate 1 Contract Tests', () {
    test('FakeAdminApprovalRepository streams initial pending users', () async {
      final repo = FakeAdminApprovalRepository();
      final users = await repo.watchPendingUsers().first;

      expect(users, isNotEmpty);
      expect(users.length, 3);
      expect(users.first.email, 'aarav.p@ch.students.amrita.edu');

      repo.dispose();
    });

    test('Approving a user removes them from the pending stream', () async {
      final repo = FakeAdminApprovalRepository();

      await repo.reviewUser(
        uid: 'pending_stu_001',
        decision: ApprovalDecision.approve,
      );

      final updatedUsers = await repo.watchPendingUsers().first;
      expect(updatedUsers.length, 2);
      expect(updatedUsers.any((u) => u.uid == 'pending_stu_001'), isFalse);

      repo.dispose();
    });

    test('Rejecting a user removes them from the pending stream', () async {
      final repo = FakeAdminApprovalRepository();

      await repo.reviewUser(
        uid: 'pending_stu_002',
        decision: ApprovalDecision.reject,
        reason: 'Unrecognized institutional enrollment',
      );

      final updatedUsers = await repo.watchPendingUsers().first;
      expect(updatedUsers.length, 2);
      expect(updatedUsers.any((u) => u.uid == 'pending_stu_002'), isFalse);

      repo.dispose();
    });
  });
}
