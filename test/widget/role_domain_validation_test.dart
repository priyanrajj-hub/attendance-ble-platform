import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/models/user_role.dart';
import 'package:amrita_ble_attendance/models/user_profile.dart';

void main() {
  group('Role and Institutional Domain Validation Tests', () {
    test('Role expected domains are strictly defined', () {
      expect(UserRole.student.expectedDomain, '@ch.students.amrita.edu');
      expect(UserRole.faculty.expectedDomain, '@ch.amrita.edu');
      expect(UserRole.admin.expectedDomain, '@ch.amrita.edu');
    });

    test('Valid student email domain passes domain check', () {
      final profile = UserProfile(
        uid: 'u1',
        email: 'priyanraj@ch.students.amrita.edu',
        fullName: 'Priyan Raj',
        role: UserRole.student,
        status: AccountStatus.verified,
        createdAt: DateTime.now(),
      );
      expect(profile.hasValidInstitutionalDomain, isTrue);
    });

    test('Student claiming faculty email domain fails validation', () {
      final profile = UserProfile(
        uid: 'u2',
        email: 'sneaky_student@ch.amrita.edu',
        fullName: 'Sneaky Student',
        role: UserRole.student,
        status: AccountStatus.verified,
        createdAt: DateTime.now(),
      );
      expect(profile.hasValidInstitutionalDomain, isFalse);
    });

    test('Commercial email domain (gmail) fails validation', () {
      final profile = UserProfile(
        uid: 'u3',
        email: 'outsider@gmail.com',
        fullName: 'Outsider',
        role: UserRole.student,
        status: AccountStatus.pendingVerification,
        createdAt: DateTime.now(),
      );
      expect(profile.hasValidInstitutionalDomain, isFalse);
    });
  });
}
