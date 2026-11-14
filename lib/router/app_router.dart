import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/pending_approval_screen.dart';
import '../screens/auth/rejected_screen.dart';
import '../screens/auth/suspended_screen.dart';
import '../screens/admin/admin_approval_screen.dart';
import '../screens/student/student_home_screen.dart';
import '../screens/student/attendance_history_screen.dart';
import '../screens/faculty/faculty_courses_screen.dart';
import '../screens/faculty/faculty_session_screen.dart';
import 'redirect_resolver.dart';

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    _ref.listen(userProfileProvider, (_, __) => notifyListeners());
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final authAsync = ref.read(authStateChangesProvider);
      final profileAsync = ref.read(userProfileProvider);

      final user = authAsync.value;
      final isAuthenticated = user != null;
      final isEmailVerified = user?.emailVerified ?? false;
      final isProfileLoading = isAuthenticated && isEmailVerified && profileAsync.isLoading;
      final profile = profileAsync.value;

      return RedirectResolver.resolveRedirect(
        isAuthenticated: isAuthenticated,
        isEmailVerified: isEmailVerified,
        isProfileLoading: isProfileLoading,
        profile: profile,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/rejected',
        builder: (context, state) => const RejectedScreen(),
      ),
      GoRoute(
        path: '/suspended',
        builder: (context, state) => const SuspendedScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminApprovalScreen(),
      ),
      GoRoute(
        path: '/student',
        builder: (context, state) => const StudentHomeScreen(),
        routes: [
          GoRoute(
            path: 'history',
            builder: (context, state) => const AttendanceHistoryScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/faculty',
        builder: (context, state) => const FacultyCoursesScreen(),
        routes: [
          GoRoute(
            path: 'session/:courseId',
            builder: (context, state) {
              final courseId = state.pathParameters['courseId'] ?? '';
              final courseName = state.uri.queryParameters['name'] ?? 'Class Session';
              return FacultySessionScreen(courseId: courseId, courseName: courseName);
            },
          ),
        ],
      ),
    ],
  );
});
