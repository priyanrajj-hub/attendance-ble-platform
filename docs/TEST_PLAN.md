# COMPREHENSIVE QUALITY ASSURANCE & TEST PLAN
**Amrita BLE Proximity Attendance Platform**  

---

## 1. Testing Strategy

The test plan spans multiple defensive rings:
1. **Cryptographic Bit-for-Bit Parity**: Cross-platform test vectors executed in both Python 3.13 and Dart 3.7 to ensure identical 128-bit truncated HMAC-SHA256 challenge generation.
2. **Backend Unit & Integration Tests**: Pytest async test suite with an active PostgreSQL 16 test database verifying RBAC, challenge validation, device registration, and manual overrides.
3. **Frontend Unit & Widget Tests**: Flutter test suite verifying GoRouter access guards, BLE state machines, institutional domain validation, and repository mocking.
4. **Firestore Rules Security Tests**: Mocha tests ensuring client write denials and read permissions across all roles.
5. **Physical Hardware ADB Testing**: Automated device detection and verification protocol for connected Android hardware.

---

## 2. Test Execution Matrix

| Test Suite | Framework | Scope | Pass Criteria |
|---|---|---|---|
| Flutter Unit & Widget | `flutter test` | 36 test cases | 100% Pass, 0 failures |
| Flutter Static Analysis | `flutter analyze` | Full Dart codebase | 0 issues |
| Backend Pytest Suite | `pytest -v` | 36 test cases | 100% Pass, 0 failures |
| Cross-Platform Crypto | Pytest & Flutter Test | Test vectors 1..3 | Bit-for-bit identical outputs |
| Hardware ADB Testing | `adb devices` | Physical Android / BLE | Explicit execution reporting |
