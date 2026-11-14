# Phase 1 — Auth + Biometric Login: Setup Guide

## Prerequisites

- **Flutter SDK** ≥ 3.0.0 installed and on your PATH
- A **Firebase project** created at [console.firebase.google.com](https://console.firebase.google.com)
- **Firebase CLI** installed: `npm install -g firebase-tools`
- **FlutterFire CLI** installed: `dart pub global activate flutterfire_cli`

---

## 1. Generate Flutter project scaffold

Your repo contains the Dart source code but not the platform folders. Run this
once from the project root to generate `android/`, `ios/`, `web/`, `test/`, etc.:

```bash
flutter create . --project-name attendance_ble_test --org com.example
```

> **Note:** This will NOT overwrite your existing `lib/` files or `pubspec.yaml`.

---

## 2. Configure Firebase

From the project root, run:

```bash
flutterfire configure
```

This will:
1. Prompt you to select your Firebase project.
2. Generate `lib/firebase_options.dart` with your platform-specific config.

After it completes, **update `lib/main.dart`**:

```dart
import 'firebase_options.dart';

// Change this line:
await Firebase.initializeApp();
// To:
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
```

---

## 3. Enable Firebase services

In the [Firebase Console](https://console.firebase.google.com), enable:

| Service | Where to enable |
|---|---|
| **Authentication** | Build → Authentication → Sign-in method → Email/Password → Enable |
| **Cloud Firestore** | Build → Firestore Database → Create database (start in test mode, then deploy rules) |
| **Storage** | Build → Storage → Get started |

---

## 4. Deploy Firestore security rules

The file `firestore.rules` in the repo root contains the production rules.
Deploy them:

```bash
firebase login             # if not already logged in
firebase init firestore    # select your project, accept firestore.rules as the rules file
firebase deploy --only firestore:rules
```

---

## 5. Set the first admin user

After registering your first account via the app, you need to manually grant
it admin privileges. The admin custom claim is what grants access to the
approval screen.

**Option A — Firebase CLI (recommended):**

```bash
# Replace ADMIN_UID with the Firebase Auth UID of your admin user
# (find it in Firebase Console → Authentication → Users)
node -e "
  const admin = require('firebase-admin');
  admin.initializeApp();
  admin.auth().setCustomUserClaims('ADMIN_UID', { role: 'admin' })
    .then(() => { console.log('Done'); process.exit(0); });
"
```

> This requires `firebase-admin` SDK. Install it: `npm install firebase-admin`

**Option B — Cloud Functions Shell:**

```bash
firebase functions:shell
```
Then in the shell:
```js
const admin = require('firebase-admin');
admin.auth().setCustomUserClaims('ADMIN_UID', { role: 'admin' });
```

**Option C — Quick script (easiest):**

Create a file `set_admin.js`:
```js
const admin = require('firebase-admin');
const serviceAccount = require('./path-to-service-account-key.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const uid = process.argv[2];
if (!uid) { console.error('Usage: node set_admin.js <UID>'); process.exit(1); }

admin.auth().setCustomUserClaims(uid, { role: 'admin' })
  .then(() => console.log(`✓ Admin claim set for ${uid}`))
  .catch(console.error);
```

Run: `node set_admin.js YOUR_UID_HERE`

After setting the claim, the user must **log out and log back in** for the
claim to take effect.

---

## 6. Update college email domain

In `lib/services/auth_service.dart`, change the domain constant:

```dart
static const String collegeDomain = '@college.edu.in';  // ← your domain
```

---

## 7. Run the app

```bash
flutter pub get
flutter run
```

---

## 8. Android-specific notes

- Add your `google-services.json` to `android/app/` (downloaded from Firebase Console)
- The existing `android_manifest_additions.xml` in the repo root contains BLE
  permissions — these need to be merged into `android/app/src/main/AndroidManifest.xml`
  after `flutter create .` generates it.
- For biometric (`local_auth`), add to `android/app/src/main/AndroidManifest.xml`:
  ```xml
  <uses-permission android:name="android.permission.USE_BIOMETRIC"/>
  ```
- Set `minSdkVersion 23` in `android/app/build.gradle` (required by `local_auth`).

## 9. iOS-specific notes

- Add `GoogleService-Info.plist` to `ios/Runner/` via Xcode
- Merge `ios_info_plist_additions.xml` entries into `ios/Runner/Info.plist`
- For Face ID, add to `Info.plist`:
  ```xml
  <key>NSFaceIDUsageDescription</key>
  <string>Confirm your identity to log in</string>
  ```
