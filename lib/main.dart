import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/role_select_screen.dart';
import 'screens/admin_approval_screen.dart';

/// NOTE: After running `flutterfire configure`, import firebase_options.dart:
/// import 'firebase_options.dart';
/// and pass `DefaultFirebaseOptions.currentPlatform` to Firebase.initializeApp().

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  // TODO: After running `flutterfire configure`, change this to:
  //   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Firebase.initializeApp();

  // Configure local Firebase Emulators in debug mode only.
  if (kDebugMode) {
    // Replace with your actual local computer IP address (e.g. '192.168.1.15') if testing on physical phone.
    // On web/desktop platforms, 'localhost' is automatically supported.
    const String localComputerIp = '192.168.1.15';
    final host = kIsWeb ? 'localhost' : localComputerIp;

    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFunctions.instance.useFunctionsEmulator(host, 5001);
    debugPrint('Local emulators initialized for Auth (9099) and Functions (5001) at $host. Firestore remains connected to the cloud.');
  }

  runApp(const AttendanceBleTestApp());
}


class AttendanceBleTestApp extends StatelessWidget {
  const AttendanceBleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/role-select': (_) => const RoleSelectScreen(),
        '/admin': (_) => const AdminApprovalScreen(),
      },
    );
  }
}
