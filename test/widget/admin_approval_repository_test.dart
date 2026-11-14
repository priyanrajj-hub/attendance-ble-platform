import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/models/user_role.dart';
import 'package:amrita_ble_attendance/repositories/admin_approval_repository.dart';

class _TestFakeAdminApprovalRepository implements AdminApprovalRepository {
  late final StreamController<List<PendingUser>> _controller;
  final List<PendingUser> _users = [
    PendingUser(
      uid: 'pending_001',
      email: 'stu1@ch.students.amrita.edu',
      fullName: 'Student One',
      role: UserRole.student,
      createdAt: DateTime.now(),
    ),
    PendingUser(
      uid: 'pending_002',
      email: 'stu2@ch.students.amrita.edu',
      fullName: 'Student Two',
      role: UserRole.student,
      createdAt: DateTime.now(),
    ),
  ];

  _TestFakeAdminApprovalRepository() {
    _controller = StreamController<List<PendingUser>>.broadcast(
      onListen: () {
        _controller.add(List.unmodifiable(_users));
      },
    );
  }

  @override
  Stream<List<PendingUser>> watchPendingUsers() => _controller.stream;

  @override
  Future<void> reviewUser({
    required String uid,
    required ApprovalDecision decision,
    String? reason,
  }) async {
    _users.removeWhere((u) => u.uid == uid);
    _controller.add(List.unmodifiable(_users));
  }

  @override
  Future<void> resetDevice({required String uid}) async {}

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('AdminApprovalRepository Interface Tests', () {
    test('Streams initial pending users', () async {
      final repo = _TestFakeAdminApprovalRepository();
      final users = await repo.watchPendingUsers().first;

      expect(users, isNotEmpty);
      expect(users.length, 2);
      expect(users.first.email, 'stu1@ch.students.amrita.edu');

      repo.dispose();
    });

    test('Approving a user removes them from the pending stream', () async {
      final repo = _TestFakeAdminApprovalRepository();

      final firstEvent = repo.watchPendingUsers().first;
      final users = await firstEvent;
      expect(users.length, 2);

      final nextEvent = repo.watchPendingUsers().skip(1).first;
      await repo.reviewUser(
        uid: 'pending_001',
        decision: ApprovalDecision.approve,
      );

      final updatedUsers = await nextEvent;
      expect(updatedUsers.length, 1);
      expect(updatedUsers.any((u) => u.uid == 'pending_001'), isFalse);

      repo.dispose();
    });
  });
}
