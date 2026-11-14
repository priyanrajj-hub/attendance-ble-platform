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

/// Stream provider for the authenticated user's profile from Firestore.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
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
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthController(this._auth, this._firestore) : super(const AsyncValue.data(null));

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
    String? rollNo,
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
        // Send email verification link
        await user.sendEmailVerification();

        // Create pending user profile in Firestore conforming to rules
        final profileData = <String, dynamic>{
          'name': fullName.trim(),
          'email': trimmedEmail,
          'role': role.firestoreKey,
          'status': 'pending_verification',
          'createdAt': FieldValue.serverTimestamp(),
        };
        if (role == UserRole.student && rollNo != null && rollNo.isNotEmpty) {
          profileData['rollNo'] = rollNo.trim().toUpperCase();
        }

        try {
          await _firestore.collection('users').doc(user.uid).set(profileData);
        } catch (e) {
          // If profile creation fails, delete user to prevent orphaned Auth account
          await user.delete();
          rethrow;
        }
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(
    ref.watch(firebaseAuthProvider),
    FirebaseFirestore.instance,
  );
});
