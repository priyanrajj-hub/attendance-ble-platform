import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// Pre-configured verified test personas for instant field verification and demonstration.
class DemoPersonas {
  static final student = UserProfile(
    uid: 'demo_student_priyan',
    email: 'ch.en.u4cce25020@ch.students.amrita.edu',
    fullName: 'PRIYANRAJ J',
    role: UserRole.student,
    status: AccountStatus.verified,
    createdAt: DateTime(2026, 1, 1),
  );

  static final faculty = UserProfile(
    uid: 'demo_faculty_rajesh',
    email: 'r_kumar@ch.amrita.edu',
    fullName: 'Dr. Rajesh Kumar',
    role: UserRole.faculty,
    status: AccountStatus.verified,
    createdAt: DateTime(2026, 1, 1),
  );

  static final admin = UserProfile(
    uid: 'demo_admin_amrita',
    email: 'admin@ch.amrita.edu',
    fullName: 'Chief Administrator',
    role: UserRole.admin,
    status: AccountStatus.verified,
    createdAt: DateTime(2026, 1, 1),
  );
}

/// Demo user profile state for instant multi-role testing and persona switching.
final demoProfileProvider = StateProvider<UserProfile?>((ref) => null);

/// Stream provider for the authenticated user's profile from Firestore or active demo session.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final demoProfile = ref.watch(demoProfileProvider);
  if (demoProfile != null) {
    return Stream.value(demoProfile);
  }

  final authUser = ref.watch(authStateChangesProvider).value;
  if (authUser == null) {
    return Stream.value(null);
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(authUser.uid)
      .snapshots()
      .map((doc) {
    if (!doc.exists || doc.data() == null) return null;
    return UserProfile.fromMap(doc.data()!, doc.id);
  });
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthController(this._ref, this._auth, this._firestore) : super(const AsyncValue.data(null));

  Future<void> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
  }) async {
    state = const AsyncValue.loading();
    try {
      final trimmedEmail = email.trim().toLowerCase();
      if (!trimmedEmail.endsWith(role.expectedDomain)) {
        throw ArgumentError(
          'Email domain mismatch: ${role.displayName} accounts must use ${role.expectedDomain}',
        );
      }

      final cred = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      final user = cred.user;
      if (user != null) {
        // Send email verification link safely
        try {
          await user.sendEmailVerification();
        } catch (e) {
          debugPrint('sendEmailVerification notice: $e');
        }

        // Create pending user profile in Firestore
        final profile = UserProfile(
          uid: user.uid,
          email: trimmedEmail,
          fullName: fullName.trim(),
          role: role,
          status: AccountStatus.pendingVerification,
          verifiedBy: null,
          verifiedAt: null,
          createdAt: DateTime.now(),
        );

        try {
          await _firestore.collection('users').doc(user.uid).set(profile.toMap());
        } catch (e) {
          debugPrint('Firestore profile document write notice: $e');
        }
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    _ref.read(demoProfileProvider.notifier).state = null;
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(
    ref,
    ref.watch(firebaseAuthProvider),
    FirebaseFirestore.instance,
  );
});
