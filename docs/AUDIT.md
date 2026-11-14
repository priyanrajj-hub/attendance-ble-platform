# Repository & Architecture Security Audit (Phase 0)

**Date**: 2026-11-12  
**Target Repository**: `attendance-ble-platform`  
**Classification**: High-Priority Architecture & Security Review  

---

## 1. Executive Summary

This audit establishes the baseline architectural state, technical debt, and security vulnerabilities present in the `attendance-ble-platform` repository prior to Phase 1. 

A thorough review of the git history, Firestore security rules, client-side Dart code, and authentication logic identified several critical architectural regressions and security bypasses introduced in earlier iterations (notably commits `135c35a`, `27fa6a5`, and `b7adb06`).

---

## 2. Cryptographic & BLE Security Analysis

### 2.1. HMAC Key Lifecycle, Access Control, and Proxy Derivation

#### Where does the HMAC key come from?
- The session secret (`hmacSecret`) is generated client-side on the faculty device in `SessionService.createSession()` using Dart's `Random.secure()` generating 32 random bytes, base64Url encoded:
  ```dart
  final hmacSecret = TokenService.generateSessionSecret();
  ```
- The secret is written to Firestore at path `sessions/{sessionId}/private/details`:
  ```dart
  await sessionRef.collection('private').doc('details').set({
    'hmacSecret': hmacSecret,
    'facultyId': user.uid,
  });
  ```

#### Who can read the session secret?
- In `firestore.rules`, access is restricted to the owning faculty member or admin:
  ```javascript
  match /private/details {
    allow read: if request.auth != null && request.auth.token.email_verified == true &&
                  (resource.data.facultyId == request.auth.uid || isAdmin());
  }
  ```
- Students **cannot** read `sessions/{sessionId}/private/details` directly via Firestore SDK.

#### Can a student derive another student's token?
**YES. In the current design, proxy attendance is trivial if any student captures a token.**

**Root Cause**:
1. In `TokenService.generateToken()`:
   ```dart
   static String generateToken(String sessionId, String secret) {
     final bucket = currentTimeBucket();
     final message = '$sessionId:$bucket';
     final key = utf8.encode(secret);
     final hmacResult = Hmac(sha256, key).convert(utf8.encode(message));
     return hmacResult.toString().substring(0, 16);
   }
   ```
   The HMAC input message is strictly `"$sessionId:$bucket"`. **It does not include the student's UID.**
2. Consequently, for any 30-second window, the generated HMAC token is **identical for every student in the lecture**.
3. In `student_broadcast_screen.dart`, the advertised BLE payload is:
   ```dart
   [studentUid (first 8 bytes) | hmacToken (8 bytes)]
   ```
4. Because the token is not bound cryptographically to the student's UID or a device-bound private key, **any student in the room can sniff the 8-byte HMAC token from the air (or take it from their own app) and broadcast it with any absent student's 8-character UID prefix.**
5. When the faculty scanner receives it, `verifyTokenFragment(sessionId, secret, tokenFragment)` only checks if the token fragment matches `HMAC(secret, "$sessionId:$bucket")`. It does not and cannot verify that the broadcast originated from the student whose UID is attached.

**Remediation**:
- The student token must be bound to `{sessionId, studentUid, timestamp, deviceKeySignature}` (Phase 2 & Phase 3 target architecture).

---

### 2.2. 8-Byte UID Prefix Truncation & Collision Risk

In `TokenService.encodeBlePayload()`:
```dart
final uidBytes = utf8.encode(
    studentUid.substring(0, studentUid.length > 8 ? 8 : studentUid.length));
```
- Firebase Authentication UIDs are 28 alphanumeric characters (128 bits of entropy).
- Truncating UIDs to the first 8 characters reduces entropy to ~48 bits.
- Under the birthday paradox, across an institutional roll of thousands of students, the probability of two students sharing the same 8-character prefix is significant.
- Commit `bcebebd` attempted to mitigate this by having the faculty scanner perform a reverse prefix lookup and throw an exception if multiple users match:
  ```dart
  if (matchingDocs.length > 1) {
    throw Exception('Ambiguous UID prefix: collision detected');
  }
  ```
- **Consequence**: This causes the faculty scanner to fail and crash/abort attendance collection whenever two enrolled students collide, rather than resolving the collision.
- **Remediation**: The student identifier must either be mapped to a compact unique integer ID allocated server-side, or attendance verification must submit the full signed challenge to the API.

---

## 3. Vulnerability & Technical Debt Matrix

| ID | Issue Description | Severity | Impact | Owning Phase |
| :--- | :--- | :--- | :--- | :--- |
| **SEC-01** | **Soft-Failing Biometrics**: In `auth_service.dart`, `performBiometricAuth()` failure is caught and ignored (`// Soft fail`). | **HIGH** | Students can bypass device biometric checks completely during login and check-in. | **Phase 2** |
| **SEC-02** | **Direct Faculty Client Attendance Writes**: Commit `b7adb06` removed Cloud Functions, allowing the faculty mobile app to write directly to `sessions/{id}/attendance/{studentId}` in Firestore. | **HIGH** | The mobile client is untrusted; client-side attendance commits violate server authority and invite client tampering. | **Phase 3** |
| **SEC-03** | **Unbound HMAC Signature (Proxy Vulnerability)**: The rotating token does not cryptographically bind the student's UID. | **HIGH** | One student present in the room can broadcast attendance on behalf of multiple absent peers. | **Phase 2 / Phase 3** |
| **SEC-04** | **8-Byte UID Prefix Truncation Collisions**: Truncated 8-char UID prefixes cause scanner ambiguity and failures on collision. | **MEDIUM** | Inability to record attendance for colliding students in larger class rosters. | **Phase 2 / Phase 3** |
| **SEC-05** | **Committed Build Artifacts & Historical Bloat**: A 52 MB APK (`attendance_ble_final.apk`), `debug.log`, and `firebase.json.bak` tracked in git; 100+ MB of node binaries in git history. | **MEDIUM** | Repo bloat (97 MB clone size), tracking ephemeral build files. | **Phase 0** |
| **SEC-06** | **Committed Firebase Configuration (`google-services.json`)**: Live Google Web API key and project metadata committed to public repository. | **MEDIUM** | Key exposure on public GitHub repo. | **Phase 0** |
| **SEC-07** | **Zero Unit Test Coverage in Flutter**: `test/widget_test.dart` contained only a dummy canary test (`expect(true, isTrue)`). | **MEDIUM** | No automated regression verification for mobile state, HMAC derivation, or UI components. | **Phase 0 / Phase 2** |

---

## 4. Google API Key Hardening & Firebase App Check Guide

`android/app/google-services.json` contains Google Web API key `AIzaSyB6ijLL...`. Because this repository is public, the key has been exposed in git history. 

### Mandatory Google Cloud Console Remediation:
1. **Restrict Key by Application (Android App)**:
   - Go to Google Cloud Console → **APIs & Services** → **Credentials**.
   - Select the API key used by Firebase.
   - Under **Application restrictions**, select **Android apps**.
   - Add an allowed item with:
     - Package Name: `com.attendance.ble.amrita_ble_attendance`
     - SHA-1 Certificate Fingerprint: Add your debug keystore SHA-1 AND release keystore SHA-1.
2. **Restrict Key by API Scope**:
   - Under **API restrictions**, select **Restrict key**.
   - Enable ONLY:
     - *Firebase Authentication API*
     - *Cloud Firestore API*
     - *Token Service API / Cloud Storage* (if used)
   - Do NOT allow generic Google Cloud APIs.
3. **Enable Firebase App Check**:
   - In Firebase Console, navigate to **App Check**.
   - Register the Android app with **Play Integrity**.
   - Register the iOS app with **DeviceCheck / App Attest**.
   - Enforce App Check on Cloud Firestore and Authentication so unauthorized HTTP clients or scripts cannot invoke Firebase APIs even with the API key.

---

## 5. Configuration Injection for CI & Fresh Clones

To ensure removing `google-services.json` from git tracking does not break builds:

1. **GitHub Actions CI Workflow**:
   - In GitHub Repository Settings → Secrets and Variables → Actions, add secret `GOOGLE_SERVICES_JSON_BASE64`.
   - Value: Generated by running `base64 -w 0 android/app/google-services.json` (or `[Convert]::ToBase64String([IO.File]::ReadAllBytes('android/app/google-services.json'))` on Windows).
   - `.github/workflows/flutter-ci.yml` automatically restores this file prior to build/analyze steps.
2. **Fresh Developer Clones**:
   - Developers copy `android/app/google-services.json.example` to `android/app/google-services.json`.
   - Developers download their assigned `google-services.json` directly from the Firebase project settings.
   - The file is permanently ignored in `.gitignore`.
