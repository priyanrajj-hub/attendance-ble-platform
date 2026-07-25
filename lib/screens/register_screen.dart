import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../services/auth_service.dart';

/// Registration screen — collects profile info, creates Firebase Auth
/// account, uploads photo, and writes a Firestore doc with
/// `status: "pending_verification"`.
///
/// The account is NOT usable until an admin flips the status to `"verified"`
/// via the [AdminApprovalScreen].
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  final _nameCtrl = TextEditingController();
  final _rollCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _parentEmailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  XFile? _profilePhoto;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _errorMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rollCtrl.dispose();
    _emailCtrl.dispose();
    _parentEmailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked != null) {
      setState(() => _profilePhoto = picked);
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (_profilePhoto == null) {
      setState(() => _errorMessage = 'Please select a profile photo.');
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // 1. Create Firebase Auth user
      final user = await _authService.register(
        _emailCtrl.text.trim(),
        _passwordCtrl.text,
      );

      // 2. Upload profile photo to Firebase Storage
      final photoRef = FirebaseStorage.instance
          .ref()
          .child('users/${user.uid}/profile.jpg');
      await photoRef.putFile(File(_profilePhoto!.path));
      final photoUrl = await photoRef.getDownloadURL();

      // 3. Write Firestore user doc
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameCtrl.text.trim(),
        'rollNo': _rollCtrl.text.trim(),
        'role': 'student',
        'email': _emailCtrl.text.trim(),
        'parentEmail': _parentEmailCtrl.text.trim(),
        'photoUrl': photoUrl,
        'status': 'pending_verification',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // 4. Sign out — account isn't usable until admin verifies
      await _authService.signOut();

      if (!mounted) return;

      // Show success and go back to login
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Registration Submitted'),
          content: const Text(
            'Your account has been created and is pending admin verification. '
            'You will be able to log in once an administrator approves your account.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(); // back to login
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Registration failed. Please try again.\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Profile photo picker ──
                Center(
                  child: GestureDetector(
                    onTap: _pickPhoto,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      backgroundImage: _profilePhoto != null
                          ? FileImage(File(_profilePhoto!.path))
                          : null,
                      child: _profilePhoto == null
                          ? Icon(Icons.camera_alt,
                              size: 32,
                              color: colorScheme.onSurfaceVariant)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to select profile photo',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 20),

                // ── Full name ──
                TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Name is required.' : null,
                ),
                const SizedBox(height: 14),

                // ── Roll number ──
                TextFormField(
                  controller: _rollCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Roll Number',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Roll number is required.'
                      : null,
                ),
                const SizedBox(height: 14),

                // ── College email ──
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'College Email',
                    hintText: 'you${AuthService.collegeDomain}',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Email is required.';
                    if (!_authService.isCollegeDomain(v)) {
                      return 'Only ${AuthService.collegeDomain} emails are allowed.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Parent Email ──
                TextFormField(
                  controller: _parentEmailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Parent Email',
                    prefixIcon: Icon(Icons.family_restroom),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Parent email is required.';
                    }
                    if (!v.contains('@')) return 'Enter a valid email.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Password ──
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Password is required.';
                    if (v.length < 6) return 'At least 6 characters required.';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Confirm password ──
                TextFormField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handleRegister(),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  validator: (v) {
                    if (v != _passwordCtrl.text) return 'Passwords do not match.';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // ── Error message ──
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: colorScheme.onErrorContainer, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Register button ──
                FilledButton(
                  onPressed: _loading ? null : _handleRegister,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Register',
                          style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
