import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/pending_approval_screen.dart';
import '../screens/admin/admin_approval_screen.dart';
import '../screens/student/student_home_screen.dart';
import '../screens/student/attendance_history_screen.dart';
import '../screens/faculty/faculty_courses_screen.dart';
import '../screens/faculty/faculty_session_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final profileState = ref.watch(userProfileProvider);

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: false,
    redirect: (BuildContext context, GoRouterState state) {
      final user = authState.value;
      final profile = profileState.value;
      final isAuthRoute = state.matchedLocation == '/login' || state.matchedLocation == '/register';

      // 1. Unauthenticated users can only visit login or register
      if (user == null) {
        return isAuthRoute ? null : '/login';
      }

      // 2. Email verification gate
      if (!user.emailVerified) {
        return state.matchedLocation == '/verify-email' ? null : '/verify-email';
      }

      // If user is authenticated and verified, redirect away from auth routes
      if (isAuthRoute || state.matchedLocation == '/verify-email') {
        if (profile == null || !profile.isVerified) {
          return '/pending-approval';
        }
        switch (profile.role) {
          case UserRole.student:
            return '/student';
          case UserRole.faculty:
            return '/faculty';
          case UserRole.admin:
            return '/admin';
        }
      }

      // 3. Admin approval gate
      if (profile != null && !profile.isVerified) {
        return state.matchedLocation == '/pending-approval' ? null : '/pending-approval';
      }

      // 4. Role-based routing guards
      if (profile != null && profile.isVerified) {
        final loc = state.matchedLocation;
        if (profile.role == UserRole.student && (loc.startsWith('/faculty') || loc.startsWith('/admin'))) {
          return '/student';
        }
        if (profile.role == UserRole.faculty && (loc.startsWith('/student') || loc.startsWith('/admin'))) {
          return '/faculty';
        }
        if (profile.role == UserRole.admin && (loc.startsWith('/student') || loc.startsWith('/faculty'))) {
          return '/admin';
        }
      }

      return null;
    },
    routes: [
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
