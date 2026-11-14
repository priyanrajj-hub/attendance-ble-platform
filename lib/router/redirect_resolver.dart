import '../models/user_profile.dart';
import '../models/user_role.dart';

class RedirectResolver {
  static String? resolveRedirect({
    required bool isAuthenticated,
    required bool isEmailVerified,
    required bool isProfileLoading,
    required UserProfile? profile,
    required String location,
  }) {
    final isAuthRoute = location == '/login' || location == '/register';

    // 1. Unauthenticated users can only visit login or register
    if (!isAuthenticated) {
      return isAuthRoute ? null : '/login';
    }

    // 2. Email verification gate
    if (!isEmailVerified) {
      return location == '/verify-email' ? null : '/verify-email';
    }

    // 3. Loading profile state (splash route to prevent flash of wrong screen)
    if (isProfileLoading) {
      return location == '/splash' ? null : '/splash';
    }

    // 4. Status gates
    if (profile == null || profile.isPending) {
      return location == '/pending-approval' ? null : '/pending-approval';
    }

    if (profile.isRejected) {
      return location == '/rejected' ? null : '/rejected';
    }

    if (profile.isSuspended) {
      return location == '/suspended' ? null : '/suspended';
    }

    // 5. User is verified - handle redirect away from landing / gate routes
    final isGateRoute = isAuthRoute ||
        location == '/verify-email' ||
        location == '/splash' ||
        location == '/pending-approval' ||
        location == '/rejected' ||
        location == '/suspended';

    final roleHome = switch (profile.role) {
      UserRole.student => '/student',
      UserRole.faculty => '/faculty',
      UserRole.admin => '/admin',
    };

    if (isGateRoute) {
      return roleHome;
    }

    // 6. Strict Role Guards on protected routes
    if (profile.role == UserRole.student &&
        (location.startsWith('/faculty') || location.startsWith('/admin'))) {
      return '/student';
    }

    if (profile.role == UserRole.faculty &&
        (location.startsWith('/student') || location.startsWith('/admin'))) {
      return '/faculty';
    }

    if (profile.role == UserRole.admin &&
        (location.startsWith('/student') || location.startsWith('/faculty'))) {
      return '/admin';
    }

    return null;
  }
}
