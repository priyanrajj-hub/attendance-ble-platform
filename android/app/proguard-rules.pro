# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase Core, Auth, Firestore, Functions, AppCheck
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Prevent stripping of Firebase model reflection
-keepclassmembers class com.google.firebase.** {
    public *;
    protected *;
}

# Keep native BLE implementations
-keep class com.boskokg.flutter_blue_plus.** { *; }
-keep class dev.steenbakker.flutter_ble_peripheral.** { *; }

# Keep Biometric / Local Auth
-keep class io.flutter.plugins.localauth.** { *; }

# Stop missing warnings crashing the build for optional deps
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn io.flutter.plugins.**
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**
