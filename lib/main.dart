import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/portal_gate_screen.dart';
import 'screens/admin_approval_screen.dart';

/// NOTE: After running `flutterfire configure`, import firebase_options.dart
/// and pass `DefaultFirebaseOptions.currentPlatform` to Firebase.initializeApp().

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase.
  await Firebase.initializeApp();

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
      initialRoute: '/',
      routes: {
        '/': (_) => const PortalGateScreen(),
        '/admin': (_) => const AdminApprovalScreen(),
      },
    );
  }
}
