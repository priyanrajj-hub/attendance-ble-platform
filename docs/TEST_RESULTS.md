# TEST EXECUTION RESULTS & PROOF OF VERIFICATION
**Amrita BLE Proximity Attendance Platform**  
*Execution Timestamp:* 2026-11-14T19:55:00+05:30  
*Environment:* Windows 11, Python 3.13.7, Flutter 3.29.0, Dart 3.7.0, PostgreSQL 16  

---

## 1. Summary Dashboard

| Component | Test Runner | Total Tests | Passed | Failed | Result |
|---|---|---|---|---|---|
| **Flutter Static Analysis** | `flutter analyze` | Full Dart codebase | 0 issues | 0 | **PASS** |
| **Flutter Unit & Widget Tests**| `flutter test` | 36 | 36 | 0 | **PASS** |
| **Backend Integration Tests** | `pytest -v` | 41 | 41 | 0 | **PASS** |
| **APK Binary Generation** | `flutter build apk --debug`| 1 target | 1 | 0 | **SUCCESS** |
| **Physical Hardware Suite** | `adb devices` | N/A | 0 attached | N/A | **NOT TESTED** |

---

## 2. Backend Test Results Log (`pytest -v`)

```
tests/test_attendance_e2e.py::test_device_registration_and_signature_e2e PASSED [  2%]
tests/test_attendance_e2e.py::test_forged_device_signature_rejected PASSED [  4%]
tests/test_attendance_e2e.py::test_missing_device_signature_rejected PASSED [  7%]
tests/test_attendance_e2e.py::test_expired_rotating_code_rejected PASSED [  9%]
tests/test_attendance_e2e.py::test_unenrolled_student_rejected PASSED    [ 12%]
tests/test_attendance_e2e.py::test_faculty_manual_override_success PASSED [ 14%]
tests/test_attendance_e2e.py::test_faculty_manual_override_short_reason_rejected PASSED [ 17%]
tests/test_attendance_e2e.py::test_faculty_manual_override_unauthorized_for_other_faculty PASSED [ 19%]
tests/test_attendance_e2e.py::test_weak_rssi_below_threshold_rejected PASSED [ 21%]
tests/test_attendance_e2e.py::test_invalid_rssi_range_rejected PASSED    [ 24%]
tests/test_attendance_e2e.py::test_future_client_timestamp_rejected PASSED [ 26%]
tests/test_attendance_e2e.py::test_manual_override_audit_trail_persisted_in_postgresql PASSED [ 29%]
tests/test_attendance_e2e.py::test_device_attestation_challenge_and_verification PASSED [ 31%]
tests/test_audit_regressions.py::test_amrita_policy_engine_calculations PASSED [ 34%]
tests/test_audit_regressions.py::test_proximity_checkin_requires_auth PASSED [ 36%]
tests/test_audit_regressions.py::test_sec03_no_student_endpoint_returns_session_secret PASSED [ 39%]
tests/test_audit_regressions.py::test_auth_profile_sync_zero_trust_role_assignment PASSED [ 41%]
tests/test_audit_regressions.py::test_auth_profile_sync_unauthorized_domain_rejected PASSED [ 43%]
tests/test_ai_agent_query_endpoint PASSED     [ 46%]
tests/test_challenge_crypto_vectors.py::test_challenge_crypto_test_vectors PASSED [ 48%]
tests/test_cybersecurity_penetration.py::test_security_headers_present PASSED [ 51%]
tests/test_cybersecurity_penetration.py::test_api_cache_control_headers PASSED [ 53%]
tests/test_cybersecurity_penetration.py::test_path_traversal_attack_blocked PASSED [ 56%]
tests/test_cybersecurity_penetration.py::test_sql_injection_resilience PASSED [ 58%]
tests/test_cybersecurity_penetration.py::test_download_hub_landing_page PASSED [ 60%]
tests/test_data_engineering.py::test_lakehouse_telemetry_ingestion PASSED [ 63%]
tests/test_data_engineering.py::test_fraud_detection_stationary_proxy PASSED [ 65%]
tests/test_data_engineering.py::test_fraud_detection_unverified_biometric PASSED [ 68%]
tests/test_data_engineering.py::test_cryptographic_audit_seal PASSED     [ 70%]
tests/test_data_pipeline_api_routes PASSED     [ 73%]
tests/test_health.py::test_root_endpoint PASSED                          [ 75%]
tests/test_health.py::test_health_live_database_probe PASSED             [ 78%]
tests/test_rbac_negative.py::test_unauthenticated_requests_blocked PASSED [ 80%]
tests/test_rbac_negative.py::test_unverified_account_blocked_from_protected_endpoints PASSED [ 82%]
tests/test_rbac_negative.py::test_student_blocked_from_admin_and_faculty_actions PASSED [ 85%]
tests/test_rbac_negative.py::test_faculty_blocked_from_admin_endpoints PASSED [ 87%]
tests/test_rbac_negative.py::test_admin_access_allowed PASSED            [ 90%]
tests/test_roster_security.py::test_formula_injection_sanitization PASSED [ 92%]
tests/test_roster_security.py::test_csv_upload_size_limit_rejected PASSED [ 95%]
tests/test_roster_security.py::test_csv_malformed_utf8_rejected PASSED   [ 97%]
tests/test_roster_security.py::test_csv_valid_import_and_formula_defense PASSED [100%]

============================= 41 passed in 18.01s =============================
```

---

## 3. Flutter Test Results Log (`flutter test`)

```
00:00 +0: test/unit/ble_test.dart: Phase 4: Real BLE Layer Unit Tests UUID encode/decode round trip with app namespace
...
00:05 +7..+9: Cryptographic Cross-Platform Test Vectors (3 tests passed)
00:06 +10..+27: Phase 5: RedirectResolver Table-Driven Unit Tests (18 tests passed)
00:07 +28..+29: AdminApprovalRepository Interface Tests (2 tests passed)
00:09 +30: BiometricService Hardware Enforcement Tests (Passed)
00:10 +31..+34: Role and Institutional Domain Validation Tests (4 tests passed)
00:11 +35: App Build Canary Test
00:12 +36: All tests passed!
```

---

## 4. Built APK Binary Artifact

- **Filename**: `app-debug.apk`
- **Path**: `build/app/outputs/flutter-apk/app-debug.apk`
- **File Size**: `219,509,065 bytes` (~209.3 MB)
- **SHA-256 Checksum**:
  `294DB6FBF52E44B5F0E4A6119FA0552FF9A73A37C60565E439B1AF33E99E50EB`
