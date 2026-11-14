# TEST EXECUTION RESULTS & PROOF OF VERIFICATION
**Amrita BLE Proximity Attendance Platform**  
*Execution Timestamp:* 2026-11-14T21:25:00+05:30  
*Environment:* Windows 11, Python 3.13.7, Flutter 3.29.0, Dart 3.7.0, PostgreSQL 16  

---

## 1. Summary Dashboard

| Component | Test Runner | Total Tests | Passed | Failed | Result |
|---|---|---|---|---|---|
| **Flutter Static Analysis** | `flutter analyze` | Full Dart codebase | 0 issues | 0 | **PASS** |
| **Flutter Unit & Widget Tests**| `flutter test` | 36 | 36 | 0 | **PASS** |
| **Backend Integration Tests** | `pytest -v` | 53 | 53 | 0 | **PASS** |
| **APK Binary Generation** | `flutter build apk --debug`| 1 target | 1 | 0 | **SUCCESS** |
| **Physical Hardware Suite** | `adb devices` | N/A | 0 attached | N/A | **NOT TESTED** |

---

## 2. Backend Test Results Log (`pytest -v`)

```
tests/test_attendance_calculation.py::test_attendance_calculation_edge_cases PASSED [  1%]
tests/test_attendance_e2e.py::test_device_registration_and_signature_e2e PASSED [  3%]
tests/test_attendance_e2e.py::test_forged_device_signature_rejected PASSED [  5%]
tests/test_attendance_e2e.py::test_missing_device_signature_rejected PASSED [  7%]
tests/test_attendance_e2e.py::test_expired_rotating_code_rejected PASSED [  9%]
tests/test_attendance_e2e.py::test_unenrolled_student_rejected PASSED    [ 11%]
tests/test_attendance_e2e.py::test_faculty_manual_override_success PASSED [ 13%]
tests/test_attendance_e2e.py::test_faculty_manual_override_short_reason_rejected PASSED [ 15%]
tests/test_attendance_e2e.py::test_faculty_manual_override_unauthorized_for_other_faculty PASSED [ 16%]
tests/test_attendance_e2e.py::test_weak_rssi_below_threshold_rejected PASSED [ 18%]
tests/test_attendance_e2e.py::test_invalid_rssi_range_rejected PASSED    [ 20%]
tests/test_attendance_e2e.py::test_future_client_timestamp_rejected PASSED [ 22%]
tests/test_attendance_e2e.py::test_manual_override_audit_trail_persisted_in_postgresql PASSED [ 24%]
tests/test_attendance_e2e.py::test_device_attestation_challenge_and_verification PASSED [ 26%]
tests/test_audit_regressions.py::test_amrita_policy_engine_calculations PASSED [ 28%]
tests/test_audit_regressions.py::test_proximity_checkin_requires_auth PASSED [ 30%]
tests/test_audit_regressions.py::test_sec03_no_student_endpoint_returns_session_secret PASSED [ 32%]
tests/test_audit_regressions.py::test_auth_profile_sync_zero_trust_role_assignment PASSED [ 33%]
tests/test_audit_regressions.py::test_auth_profile_sync_unauthorized_domain_rejected PASSED [ 35%]
tests/test_ai_agent_query_endpoint PASSED     [ 37%]
tests/test_challenge_crypto_vectors.py::test_challenge_crypto_test_vectors PASSED [ 39%]
tests/test_cybersecurity_penetration.py::test_security_headers_present PASSED [ 41%]
tests/test_cybersecurity_penetration.py::test_api_cache_control_headers PASSED [ 43%]
tests/test_cybersecurity_penetration.py::test_path_traversal_attack_blocked PASSED [ 45%]
tests/test_cybersecurity_penetration.py::test_sql_injection_resilience PASSED [ 47%]
tests/test_cybersecurity_penetration.py::test_download_hub_landing_page PASSED [ 49%]
tests/test_data_engineering.py::test_lakehouse_telemetry_ingestion PASSED [ 50%]
tests/test_data_engineering.py::test_fraud_detection_stationary_proxy PASSED [ 52%]
tests/test_data_engineering.py::test_fraud_detection_unverified_biometric PASSED [ 54%]
tests/test_data_engineering.py::test_cryptographic_audit_seal PASSED     [ 56%]
tests/test_data_engineering.py::test_data_pipeline_api_routes PASSED     [ 58%]
tests/test_dispute_concurrency.py::test_concurrent_dispute_submission_race PASSED [ 60%]
tests/test_dispute_concurrency.py::test_concurrent_dispute_resolution_pessimistic_lock PASSED [ 62%]
tests/test_disputes_and_auth_scoping.py::test_student_submit_dispute_and_lifecycle PASSED [ 64%]
tests/test_disputes_and_auth_scoping.py::test_student_dispute_unenrolled_rejected PASSED [ 66%]
tests/test_disputes_and_auth_scoping.py::test_cross_faculty_authorization_defenses PASSED [ 67%]
tests/test_health.py::test_root_endpoint PASSED                          [ 69%]
tests/test_health.py::test_health_live_database_probe PASSED             [ 71%]
tests/test_parquet_and_telemetry_recovery.py::test_parquet_partitioned_storage_and_append_integrity PASSED [ 73%]
tests/test_parquet_and_telemetry_recovery.py::test_duckdb_reload_persisted_telemetry_after_restart PASSED [ 75%]
tests/test_parquet_and_telemetry_recovery.py::test_interrupted_write_recovery PASSED [ 77%]
tests/test_parquet_and_telemetry_recovery.py::test_concurrent_parquet_writes PASSED [ 79%]
tests/test_rbac_negative.py::test_unauthenticated_requests_blocked PASSED [ 81%]
tests/test_rbac_negative.py::test_unverified_account_blocked_from_protected_endpoints PASSED [ 83%]
tests/test_rbac_negative.py::test_student_blocked_from_admin_and_faculty_actions PASSED [ 84%]
tests/test_rbac_negative.py::test_faculty_blocked_from_admin_endpoints PASSED [ 86%]
tests/test_rbac_negative.py::test_admin_access_allowed PASSED            [ 88%]
tests/test_roster_security.py::test_formula_injection_sanitization PASSED [ 90%]
tests/test_roster_security.py::test_csv_upload_size_limit_rejected PASSED [ 92%]
tests/test_roster_security.py::test_csv_malformed_utf8_rejected PASSED   [ 94%]
tests/test_roster_security.py::test_csv_valid_import_and_formula_defense PASSED [ 96%]
tests/test_session_secret_security.py::test_session_secret_at_rest_envelope_encryption_and_zero_leakage PASSED [ 98%]
tests/test_telemetry_authorization.py::test_telemetry_authorization_and_integrity PASSED [100%]

============================= 53 passed in 20.22s =============================
```

---

## 3. Flutter Test Results Log (`flutter test`)

```
00:00 +0: loading C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/ble_test.dart
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
00:01 +10: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Unauthenticated at /student redirects to /login
00:01 +11: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Unauthenticated at /login is allowed
00:01 +12: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Unauthenticated at /register is allowed
00:01 +13: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Authenticated with unverified email redirects to /verify-email
00:01 +14: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Authenticated with unverified email at /verify-email is allowed
00:01 +15: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Profile loading redirects to /splash
00:01 +16: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Pending approval status redirects to /pending-approval
00:01 +17: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Rejected status redirects to /rejected
00:01 +18: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Suspended status redirects to /suspended
00:01 +19: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified student at /login redirects to /student
00:01 +20: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified student attempting /faculty redirects to /student
00:01 +21: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified student attempting /admin redirects to /student
00:01 +22: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified student at /student is allowed
00:01 +23: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified faculty attempting /student redirects to /faculty
00:01 +24: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified faculty attempting /admin redirects to /faculty
00:01 +25: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified faculty at /faculty is allowed
00:01 +26: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified admin attempting /student redirects to /admin
00:01 +27: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/router_test.dart: Phase 5: RedirectResolver Table-Driven Unit Tests Verified admin at /admin is allowed
00:01 +28: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/admin_approval_repository_test.dart: AdminApprovalRepository Interface Tests Streams initial pending users
00:01 +29: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/admin_approval_repository_test.dart: AdminApprovalRepository Interface Tests Approving a user removes them from the pending stream
00:03 +30: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/biometric_service_test.dart: BiometricService Hardware Enforcement Tests Without hardware/enrolled sensors, returns failure rather than simulated success
00:03 +31: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/role_domain_validation_test.dart: Role and Institutional Domain Validation Tests Role expected domains are strictly defined
00:03 +32: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/role_domain_validation_test.dart: Role and Institutional Domain Validation Tests Valid student email domain passes domain check
00:03 +33: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/role_domain_validation_test.dart: Role and Institutional Domain Validation Tests Student claiming faculty email domain fails validation
00:03 +34: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget/role_domain_validation_test.dart: Role and Institutional Domain Validation Tests Commercial email domain (gmail) fails validation
00:04 +35: C:/Users/PRIYANRAJ J/.gemini/antigravity/scratch/attendance-ble-platform/test/widget_test.dart: App Build Canary Test
00:05 +36: All tests passed!
```
