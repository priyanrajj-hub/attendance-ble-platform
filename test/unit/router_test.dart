import 'package:flutter_test/flutter_test.dart';
import 'package:amrita_ble_attendance/models/user_profile.dart';
import 'package:amrita_ble_attendance/models/user_role.dart';
import 'package:amrita_ble_attendance/router/redirect_resolver.dart';

void main() {
  group('Phase 5: RedirectResolver Table-Driven Unit Tests', () {
    final verifiedStudent = UserProfile(
      uid: 'stu1',
      email: 'stu1@ch.students.amrita.edu',
      fullName: 'Student 1',
      role: UserRole.student,
      status: AccountStatus.verified,
      createdAt: DateTime.now(),
    );

    final pendingStudent = UserProfile(
      uid: 'stu2',
      email: 'stu2@ch.students.amrita.edu',
      fullName: 'Student 2',
      role: UserRole.student,
      status: AccountStatus.pendingVerification,
      createdAt: DateTime.now(),
    );

    final rejectedStudent = UserProfile(
      uid: 'stu3',
      email: 'stu3@ch.students.amrita.edu',
      fullName: 'Student 3',
      role: UserRole.student,
      status: AccountStatus.rejected,
      createdAt: DateTime.now(),
    );

    final suspendedStudent = UserProfile(
      uid: 'stu4',
      email: 'stu4@ch.students.amrita.edu',
      fullName: 'Student 4',
      role: UserRole.student,
      status: AccountStatus.suspended,
      createdAt: DateTime.now(),
    );

    final verifiedFaculty = UserProfile(
      uid: 'fac1',
      email: 'fac1@ch.amrita.edu',
      fullName: 'Faculty 1',
      role: UserRole.faculty,
      status: AccountStatus.verified,
      createdAt: DateTime.now(),
    );

    final verifiedAdmin = UserProfile(
      uid: 'adm1',
      email: 'adm1@ch.amrita.edu',
      fullName: 'Admin 1',
      role: UserRole.admin,
      status: AccountStatus.verified,
      createdAt: DateTime.now(),
    );

    final testCases = <Map<String, dynamic>>[
      // Unauthenticated
      {
        'desc': 'Unauthenticated at /student redirects to /login',
        'auth': false,
        'emailVer': false,
        'loading': false,
        'profile': null,
        'loc': '/student',
        'expected': '/login',
      },
      {
        'desc': 'Unauthenticated at /login is allowed',
        'auth': false,
        'emailVer': false,
        'loading': false,
        'profile': null,
        'loc': '/login',
        'expected': null,
      },
      {
        'desc': 'Unauthenticated at /register is allowed',
        'auth': false,
        'emailVer': false,
        'loading': false,
        'profile': null,
        'loc': '/register',
        'expected': null,
      },

      // Authenticated but unverified email
      {
        'desc': 'Authenticated with unverified email redirects to /verify-email',
        'auth': true,
        'emailVer': false,
        'loading': false,
        'profile': null,
        'loc': '/student',
        'expected': '/verify-email',
      },
      {
        'desc': 'Authenticated with unverified email at /verify-email is allowed',
        'auth': true,
        'emailVer': false,
        'loading': false,
        'profile': null,
        'loc': '/verify-email',
        'expected': null,
      },

      // Authenticated, verified email, loading profile
      {
        'desc': 'Profile loading redirects to /splash',
        'auth': true,
        'emailVer': true,
        'loading': true,
        'profile': null,
        'loc': '/login',
        'expected': '/splash',
      },

      // Pending verification status
      {
        'desc': 'Pending approval status redirects to /pending-approval',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': pendingStudent,
        'loc': '/student',
        'expected': '/pending-approval',
      },

      // Rejected status
      {
        'desc': 'Rejected status redirects to /rejected',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': rejectedStudent,
        'loc': '/student',
        'expected': '/rejected',
      },

      // Suspended status
      {
        'desc': 'Suspended status redirects to /suspended',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': suspendedStudent,
        'loc': '/student',
        'expected': '/suspended',
      },

      // Verified Student role guards
      {
        'desc': 'Verified student at /login redirects to /student',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedStudent,
        'loc': '/login',
        'expected': '/student',
      },
      {
        'desc': 'Verified student attempting /faculty redirects to /student',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedStudent,
        'loc': '/faculty',
        'expected': '/student',
      },
      {
        'desc': 'Verified student attempting /admin redirects to /student',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedStudent,
        'loc': '/admin',
        'expected': '/student',
      },
      {
        'desc': 'Verified student at /student is allowed',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedStudent,
        'loc': '/student',
        'expected': null,
      },

      // Verified Faculty role guards
      {
        'desc': 'Verified faculty attempting /student redirects to /faculty',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedFaculty,
        'loc': '/student',
        'expected': '/faculty',
      },
      {
        'desc': 'Verified faculty attempting /admin redirects to /faculty',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedFaculty,
        'loc': '/admin',
        'expected': '/faculty',
      },
      {
        'desc': 'Verified faculty at /faculty is allowed',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedFaculty,
        'loc': '/faculty',
        'expected': null,
      },

      // Verified Admin role guards
      {
        'desc': 'Verified admin attempting /student redirects to /admin',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedAdmin,
        'loc': '/student',
        'expected': '/admin',
      },
      {
        'desc': 'Verified admin at /admin is allowed',
        'auth': true,
        'emailVer': true,
        'loading': false,
        'profile': verifiedAdmin,
        'loc': '/admin',
        'expected': null,
      },
    ];

    for (final tc in testCases) {
      test(tc['desc'] as String, () {
        final actual = RedirectResolver.resolveRedirect(
          isAuthenticated: tc['auth'] as bool,
          isEmailVerified: tc['emailVer'] as bool,
          isProfileLoading: tc['loading'] as bool,
          profile: tc['profile'] as UserProfile?,
          location: tc['loc'] as String,
        );
        expect(actual, tc['expected']);
      });
    }
  });
}
