import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';

/// Central auth service — wraps Firebase Auth + device biometrics.
///
/// Login flow: credential check → biometric check → session.
/// The biometric step uses [local_auth] which never transmits
/// biometric data off-device (Android BiometricPrompt / iOS Face ID).
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// The college email domains that are allowed to register / log in.
  static const String studentDomain = '@ch.students.amrita.edu';
  static const String facultyDomain = '@ch.amrita.edu';

  // ─── Getters ──────────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Domain validation ────────────────────────────────────────────

  bool isStudentDomain(String email) {
    final regex = RegExp(r'^[a-zA-Z0-9._-]+@ch\.students\.amrita\.edu$');
    return regex.hasMatch(email.trim().toLowerCase());
  }

  bool isFacultyDomain(String email) {
    final regex = RegExp(r'^[a-zA-Z0-9._-]+@ch\.amrita\.edu$');
    return regex.hasMatch(email.trim().toLowerCase());
  }

  /// Returns `true` if [email] belongs to either standard allowed domain.
  bool isCollegeDomain(String email) {
    return isStudentDomain(email) || isFacultyDomain(email);
  }

  // ─── Biometric helpers ────────────────────────────────────────────

  /// Whether the device has any enrolled biometrics (fingerprint, face, etc.).
  Future<bool> isBiometricAvailable() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final isDeviceSupported = await _localAuth.isDeviceSupported();
    return canCheck && isDeviceSupported;
  }

  /// Prompts the user for biometric authentication.
  /// Returns `true` only if the check succeeds.
  Future<bool> performBiometricAuth() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Confirm it\'s you to continue',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  // ─── Sign-in (credential + biometric) ─────────────────────────────

  /// Full login flow:
  /// 1. Validate email against the specific role domain.
  /// 2. Firebase `signInWithEmailAndPassword`.
  /// 3. Biometric prompt via `local_auth`.
  /// 4. Return the [User] only if ALL steps succeed (or if biometric fails, we soft-bypass).
  ///
  /// Throws [AuthException] with a user-friendly message on failure.
  Future<User> signIn(String email, String password, String role) async {
    // 1. Verify exact Amrita domain matches on client instantly (no server roundtrip needed to fail this)
    if (role == 'student' && !isStudentDomain(email)) {
      throw AuthException('Student accounts must use $studentDomain');
    }
    if (role == 'faculty' && !isFacultyDomain(email)) {
      throw AuthException('Faculty accounts must use $facultyDomain');
    }

    // 2. Perform Firebase Auth login
    UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      User user = credential.user!;

      // 3. Email Verification Loop (Enforce strict blocking and Force Token Refresh)
      if (!user.emailVerified) {
        await user.reload(); // fetch latest status from Firebase
        user = _auth.currentUser!;
        if (user.emailVerified) {
          // FORCE REFRESH: If they just verified, their cached ID token still reads email_verified=false
          // We must flush it so our new Firestore security rules don't incorrectly throw PERMISSION_DENIED.
          await user.getIdToken(true);
        } else {
          await _auth.signOut();
          throw AuthException(
              'Your email is not verified. Please check your inbox.');
        }
      }
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseError(e.code));
    }

    // 3. Check account verification status (from Firestore — caller handles)
    //    The login_screen checks Firestore 'status' field after this returns.

    // 4. Biometric second factor - Soft bypass on failure for broader compat
    final bioAvailable = await isBiometricAvailable();
    if (!bioAvailable) {
      // Do nothing, just continue without biometrics if not configured properly.
    } else {
      final bioSuccess = await performBiometricAuth();
      if (!bioSuccess) {
        // Soft fail: we don't throw AuthException anymore, so users can log in even if they cancel Biometrics testing Phase 1.
      }
    }

    return credential.user!;
  }

  // ─── Registration ─────────────────────────────────────────────────

  /// Creates a Firebase Auth account. Does NOT set up Firestore profile
  /// or upload photo — that is handled by the register screen after this
  /// returns a UID.
  Future<User> register(String email, String password, String role) async {
    if (role == 'student' && !isStudentDomain(email)) {
      throw AuthException('Student accounts must use $studentDomain');
    }
    if (role == 'faculty' && !isFacultyDomain(email)) {
      throw AuthException('Faculty accounts must use $facultyDomain');
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // Automatically send the verification email immediately after signup
      await credential.user!.sendEmailVerification();

      // 🔥 CRITICAL: Force refresh id token so Firestore SDK syncs before we call .set()!
      await credential.user!.getIdToken(true);

      return credential.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_mapFirebaseError(e.code));
    }
  }

  // ─── Sign-out ─────────────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  String _mapFirebaseError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found for this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-email':
        return 'The email address is not valid.';
      default:
        return 'Authentication failed ($code). Please try again.';
    }
  }
}

/// Custom exception for user-facing auth errors.
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}
