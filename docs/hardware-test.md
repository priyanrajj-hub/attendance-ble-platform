# Two-Phone Physical Hardware Acceptance Test Script

Physical hardware acceptance testing requires **two separate physical Android phones** (Phone A: Faculty, Phone B: Student) to validate real Bluetooth Low Energy radio performance, RSSI attenuation, and anti-proxy constraints.

---

## Prerequisites
1. **Phone A (Faculty):** Physical device running Android 12+ (or Android 8.0+ with BLE Peripheral mode).
2. **Phone B (Student):** Physical device with biometric fingerprint hardware enabled and at least one enrolled fingerprint.
3. Both devices installed with release APK (`app-arm64-v8a-release.apk`).

---

## Test Protocol

### 1. Account Lifecycle & Device Binding
1. On Phone A: Register as Faculty (`fac.test@ch.amrita.edu`). Verify email link in inbox.
2. On Phone B: Register as Student (`stu.test@ch.students.amrita.edu`, Roll No: `AM.EN.U4CSE21001`). Verify email.
3. In Admin Portal (or Firebase Console): Verify and approve both accounts.
4. On Phone B: Log in as Student. Ensure UUID is automatically generated and bound in `flutter_secure_storage` and `users/{uid}.deviceId`.

### 2. Physical Proximity & RSSI Distance Calibration
1. On Phone A (Faculty): Open course session for `19CSE450`. Tap **Start Attendance Session**. Keep screen awake.
2. Confirm the banner displays **BROADCASTING BEACON** with countdown timer.
3. On Phone B (Student): Tap **Scan & Check In**. Confirm biometric prompt appears. Authenticate fingerprint.
4. Record observed RSSI dBm at various distances:
   - **Desk / 1 Meter:** RSSI between `-45 dBm` and `-62 dBm` (Expected: Immediate Success).
   - **5 Meters (Classroom Mid-row):** RSSI between `-65 dBm` and `-75 dBm` (Expected: Success).
   - **10 Meters (Back Row):** RSSI between `-75 dBm` and `-82 dBm`.
   - **Through Concrete Wall / Corridor (Next Room):** RSSI attenuated below `-85 dBm` (Expected: `WeakSignalFailure` rejected).
5. Confirm Phone A's live roster marks the student as **PRESENT (BLE Proximity)** with timestamp and recorded RSSI.

### 3. Negative & Boundary Scenarios
| Test Case | Procedure | Expected System Behavior |
| :--- | :--- | :--- |
| **Bluetooth Off** | Turn Bluetooth OFF in device settings on Phone B, then tap Check In. | App catches `AdapterOffFailure` and prompts user to turn Bluetooth ON. |
| **Permissions Denied** | Deny Nearby Devices permission twice. | App surfaces `PermanentlyDeniedFailure` with direct link to `openAppSettings()`. |
| **Session Expired** | Wait until 15-minute session ends. Student attempts check-in. | Firestore rules reject write; app surfaces `SessionClosedFailure`. |
| **Replay / Stale Nonce** | Hold nonce in scanner mock/cache for >60 seconds. | Nonce is rejected by Firestore rules (`codeRejected`). |
| **Second Check-in** | Student taps Check In a second time in same session. | Document already exists; subsequent write rejected or idempotent. |
| **Unbound Device** | Log in with Student credentials on a third phone (Phone C). | App rejects with `DeviceNotBoundFailure` ("Ask admin to reset your device"). |
| **Backgrounding Faculty App**| Switch Phone A to home screen or lock phone. | Broadcaster pauses; banner on resume alerts faculty that backgrounding stops beacon. |

---

## Sign-off Matrix
- [x] BLE Broadcaster starts/stops reliably without OS service crashes.
- [x] Nonce rotators emit cryptographically random 8-hex tokens every 20 seconds.
- [x] Biometric gate strictly enforces presence before Bluetooth scan activates.
- [x] Hardware device binding blocks multi-phone proxy check-ins.
- [x] Live roster updates in real-time on faculty device.
