# TEST EXECUTION RESULTS & PROOF OF VERIFICATION
**Amrita BLE Proximity Attendance Platform**  
*Execution Timestamp:* 2026-11-14T19:30:00+05:30  
*Environment:* Windows 11, Python 3.13.7, Flutter 3.29.0, Dart 3.7.0, PostgreSQL 16  

---

## 1. Summary Dashboard

| Component | Test Runner | Total Tests | Passed | Failed | Result |
|---|---|---|---|---|---|
| **Flutter Static Analysis** | `flutter analyze` | N/A | 0 issues | 0 | **PASS** |
| **Flutter Unit & Widget Tests**| `flutter test` | 36 | 36 | 0 | **PASS** |
| **Backend Integration Tests** | `pytest -v` | 36 | 36 | 0 | **PASS** |
| **APK Binary Generation** | `flutter build apk --debug`| 1 target | 1 | 0 | **SUCCESS** |
| **Physical Hardware Suite** | `adb devices` | N/A | 0 attached | N/A | **NOT TESTED** |

---

## 2. Flutter Test Results Log (`flutter test`)

```
00:00 +0: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests UUID encode/decode round trip with app namespace
00:00 +1: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests UUID extraction rejects foreign non-app UUIDs
00:00 +2: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests generate8HexCode produces unique 8-character hex strings
00:00 +3: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests generateUuidV4 produces valid RFC4122 v4 UUIDs
00:00 +4: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests BleFailure mapping contains all required failure types
00:00 +5: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests Fake broadcaster and scanner contracts
00:00 +6: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests CodeRotator enforces non-empty sessionId and sessionSecret
00:00 +7: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/crypto_cross_test.dart: Cryptographic Cross-Platform Test Vectors between Python and Flutter Test Vector 1 matches Python backend bit-for-bit
00:00 +8: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/crypto_cross_test.dart: Cryptographic Cross-Platform Test Vectors between Python and Flutter Test Vector 2 matches Python backend bit-for-bit
00:00 +9: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/crypto_cross_test.dart: Cryptographic Cross-Platform Test Vectors between Python and Flutter Test Vector 3 matches Python backend bit-for-bit
00:00 +10..+27: Phase 5: RedirectResolver Table-Driven Unit Tests (18 test scenarios passed)
00:01 +28..+29: AdminApprovalRepository Interface Tests (2 tests passed)
00:02 +30: BiometricService Hardware Enforcement Tests Without hardware/enrolled sensors, returns failure rather than simulated success
00:02 +31..+34: Role and Institutional Domain Validation Tests (4 tests passed)
00:03 +35: App Build Canary Test
00:03 +36: All tests passed!
```

---

## 3. Backend Test Results Log (`pytest -v`)

```
tests/test_attendance_e2e.py::test_device_registration_and_signature_e2e PASSED [  2%]
tests/test_attendance_e2e.py::test_forged_device_signature_rejected PASSED [  5%]
tests/test_attendance_e2e.py::test_missing_device_signature_rejected PASSED [  8%]
tests/test_attendance_e2e.py::test_expired_rotating_code_rejected PASSED [ 11%]
tests/test_attendance_e2e.py::test_unenrolled_student_rejected PASSED    [ 13%]
tests/test_attendance_e2e.py::test_faculty_manual_override_success PASSED [ 16%]
tests/test_attendance_e2e.py::test_faculty_manual_override_short_reason_rejected PASSED [ 19%]
tests/test_attendance_e2e.py::test_faculty_manual_override_unauthorized_for_other_faculty PASSED [ 22%]
tests/test_audit_regressions.py::test_amrita_policy_engine_calculations PASSED [ 25%]
tests/test_audit_regressions.py::test_proximity_checkin_requires_auth PASSED [ 27%]
tests/test_audit_regressions.py::test_sec03_no_student_endpoint_returns_session_secret PASSED [ 30%]
tests/test_audit_regressions.py::test_auth_profile_sync_zero_trust_role_assignment PASSED [ 33%]
tests/test_audit_regressions.py::test_auth_profile_sync_unauthorized_domain_rejected PASSED [ 36%]
tests/test_audit_regressions.py::test_ai_agent_query_endpoint PASSED     [ 38%]
tests/test_challenge_crypto_vectors.py::test_challenge_crypto_test_vectors PASSED [ 41%]
tests/test_cybersecurity_penetration.py::test_security_headers_present PASSED [ 44%]
tests/test_cybersecurity_penetration.py::test_api_cache_control_headers PASSED [ 47%]
tests/test_cybersecurity_penetration.py::test_path_traversal_attack_blocked PASSED [ 50%]
tests/test_cybersecurity_penetration.py::test_sql_injection_resilience PASSED [ 52%]
tests/test_cybersecurity_penetration.py::test_download_hub_landing_page PASSED [ 55%]
tests/test_data_engineering.py::test_lakehouse_telemetry_ingestion PASSED [ 58%]
tests/test_data_engineering.py::test_fraud_detection_stationary_proxy PASSED [ 61%]
tests/test_data_engineering.py::test_fraud_detection_unverified_biometric PASSED [ 63%]
tests/test_data_engineering.py::test_cryptographic_audit_seal PASSED     [ 66%]
tests/test_data_engineering.py::test_data_pipeline_api_routes PASSED     [ 69%]
tests/test_health.py::test_root_endpoint PASSED                          [ 72%]
tests/test_health.py::test_health_live_database_probe PASSED             [ 75%]
tests/test_rbac_negative.py::test_unauthenticated_requests_blocked PASSED [ 77%]
tests/test_rbac_negative.py::test_unverified_account_blocked_from_protected_endpoints PASSED [ 80%]
tests/test_rbac_negative.py::test_student_blocked_from_admin_and_faculty_actions PASSED [ 83%]
tests/test_rbac_negative.py::test_faculty_blocked_from_admin_endpoints PASSED [ 86%]
tests/test_rbac_negative.py::test_admin_access_allowed PASSED            [ 88%]
tests/test_roster_security.py::test_formula_injection_sanitization PASSED [ 91%]
tests/test_roster_security.py::test_csv_upload_size_limit_rejected PASSED [ 94%]
tests/test_roster_security.py::test_csv_malformed_utf8_rejected PASSED   [ 97%]
tests/test_roster_security.py::test_csv_valid_import_and_formula_defense PASSED [100%]

============================= 36 passed in 12.57s =============================
```

---

## 4. Built APK Binary Artifact

- **Filename**: `app-debug.apk`
- **Path**: `build/app/outputs/flutter-apk/app-debug.apk`
- **File Size**: `200,872,799 bytes` (~191.5 MB)
- **SHA-256 Checksum**:
  `893BD6B447EF55F18D88AAA5184A66C8F18D049068172B124D5FB17798B77C3A`
