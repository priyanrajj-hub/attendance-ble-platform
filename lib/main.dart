import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FirebaseException? initError;
  Object? unknownError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    initError = e;
  } catch (e) {
    unknownError = e;
  }

  if (initError != null || unknownError != null) {
    runApp(
      FirebaseInitErrorApp(
        errorMessage: initError?.message ?? unknownError.toString(),
      ),
    );
    return;
  }

  runApp(
    const ProviderScope(
      child: AttendancePlatformApp(),
    ),
  );
}

class FirebaseInitErrorApp extends StatelessWidget {
  final String errorMessage;

  const FirebaseInitErrorApp({super.key, required this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text(
                      'Firebase Initialization Failed',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Connection'),
                      onPressed: () => main(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AttendancePlatformApp extends ConsumerWidget {
  const AttendancePlatformApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Amrita Attendance',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
