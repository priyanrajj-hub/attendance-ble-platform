import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (safely catch if running in offline test environment)
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase.initializeApp() warning (expected during offline dev): $e');
  }

  runApp(
    const ProviderScope(
      child: AttendancePlatformApp(),
    ),
  );
}

class AttendancePlatformApp extends ConsumerWidget {
  const AttendancePlatformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Amrita BLE Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
