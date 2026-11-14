# PHYSICAL DEVICE & HARDWARE ATTENDANCE TESTING
**Amrita BLE Proximity Attendance Platform**  
*Testing Status:* **NOT TESTED - No physical hardware connected to ADB host**  

---

## 1. ADB Host Device Enumeration

Execution of `adb devices -l` from the local development host:

```
> & "D:\android-sdk\platform-tools\adb.exe" devices -l
List of devices attached
```

*Finding:* Exactly zero (0) Android physical devices or running emulators were detected on the ADB USB/TCP daemon during this audit phase.

---

## 2. Real Hardware Test Constraints & Honesty Statement

In accordance with strict production engineering integrity principles:
- **No simulated physical passes**: This audit does NOT claim that Bluetooth Low Energy packet transmission or reception over physical airwaves has been validated on physical silicon for this commit.
- **Physical BLE Radio Tests**: **NOT TESTED** (Requires two physical BLE-capable Android/iOS devices).
- **Physical Biometric Keystore Sensor**: **NOT TESTED** (Requires physical fingerprint/Face unlock hardware).
- **Hardware Remote Attestation (Play Integrity / DeviceCheck)**: **NOT TESTED** (Requires production Google Play developer key and hardware certification).

---

## 3. Physical Hardware Execution Checklist (For On-Site QA Engineers)

When physical devices are attached to the workstation via USB debugging:
1. Ensure both devices show up under `adb devices`.
2. Install the debug APK:
   ```powershell
   adb -s <FACULTY_DEVICE_ID> install -r build/app/outputs/flutter-apk/app-debug.apk
   adb -s <STUDENT_DEVICE_ID> install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
3. Grant `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`, and `ACCESS_FINE_LOCATION` permissions.
4. On Faculty phone: Log in as faculty and start session for `CSE450`. Observe rotating 32-hex codes in debug console.
5. On Student phone: Log in as student enrolled in `CSE450`. Tap "Check In". Observe RSSI measurement and successful check-in toast.
6. Verify record in PostgreSQL:
   ```sql
   SELECT * FROM attendance_records WHERE method = 'ble_signed_nonce';
   ```
