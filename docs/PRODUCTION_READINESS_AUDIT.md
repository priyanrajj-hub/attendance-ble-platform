# Production Readiness & Architecture Security Audit
**Amrita BLE Proximity Attendance Platform**  
**Repository:** `priyanrajj-hub/attendance-ble-platform`  
**Inspected Commit:** `20252ea`  
**Classification Date:** November 2026  
**Status:** Comprehensive System Remediation  

---

## Executive Summary

This audit assesses the security, data consistency, cryptographic soundness, and production readiness of the Amrita BLE Proximity Attendance Platform. While initial implementations established mobile UI screens, BLE scanning/advertising abstractions, and backend CRUD routes, rigorous penetration analysis uncovered fundamental architectural vulnerabilities—most notably split data authority between Cloud Firestore and PostgreSQL, unverified client signatures, and decoupled challenge rotation.

This document serves as the formal architectural register for all discovered vulnerabilities, their attack vectors, root causes, required remediation, and verification status.

---

## Vulnerability & Architecture Register

### 1. ARCH-01: Dual Authority Ledger Desynchronization
- **Issue ID:** `ARCH-01`
- **Severity:** `CRITICAL`
- **File & Function:** `lib/ble/student_checkin_controller.dart:executeCheckIn` vs `backend/app/routers/checkin_stub.py:check_in`
- **Existing Behavior:** The Flutter application directly writes attendance records to Firestore at `/sessions/{sessionId}/attendance/{studentUid}`, bypassing the FastAPI backend entirely during normal mobile flow. Simultaneously, the backend provides an attendance check-in route writing to PostgreSQL `attendance_records`.
- **Exploitation Scenario:** A malicious or compromised client writes directly to Cloud Firestore using its Firebase Authentication token, bypassing backend business logic (course enrollment checks, device hardware signatures, and database audit logs). Faculty viewing PostgreSQL-backed reports see absent students who appear present on Firestore live widgets, creating irreconcilable discrepancy.
- **Root Cause:** Decentralized write architecture lacking a single authoritative attendance ledger.
- **Recommended Correction:** Establish PostgreSQL as the sole authoritative attendance ledger. The Flutter client must submit attendance check-ins exclusively to `POST /api/v1/attendance/check-in`. Cloud Firestore will serve purely as a read-only live session signaling and roster projection layer updated via backend triggers or faculty session listeners. Provide a synchronization/reconciliation script (`backend/scripts/reconcile_attendance.py`).
- **Test Required:** End-to-end integration test verifying that a check-in executed via API writes to PostgreSQL and projects to the live roster, with direct client Firestore writes restricted.
- **Final Status:** IN PROGRESS (Phase 2 & 5 Remediation)

---

### 2. SEC-01: Cryptographic Signature Omission in Backend Check-In
- **Issue ID:** `SEC-01`
- **Severity:** `CRITICAL`
- **File & Function:** `backend/app/routers/checkin_stub.py:check_in`
- **Existing Behavior:** `CheckInPayload` defines `signature: Optional[str] = None`. The endpoint accepts check-ins without validating a cryptographic signature against a registered device key, yet sets `new_record.signature_verified = True` unconditionally.
- **Exploitation Scenario:** An enrolled student outside the classroom obtains the rotating code from an in-class peer via instant messaging and submits a POST request via curl or a script. Because no signature or device attestation is verified, the attendance is accepted and marked `signature_verified=True`.
- **Root Cause:** Endpoint was initially implemented as a partial stub and lacked asymmetric signature verification service integration.
- **Recommended Correction:** Make `signature`, `public_key_fingerprint`, and `timestamp` mandatory fields in `CheckInPayload`. Implement `DeviceVerificationService` to retrieve the student's active registered device public key and verify ECDSA / RSA signature over `sessionId:challenge:timestamp`.
- **Test Required:** Pytest rejecting unsigned payloads (400), forged signatures (401/403), signatures with expired timestamps (400), and revoked device keys (403).
- **Final Status:** IN PROGRESS (Phase 4 & 5 Remediation)

---

### 3. SEC-02: Challenge Entropy & Backend Decoupling
- **Issue ID:** `SEC-02`
- **Severity:** `HIGH`
- **File & Function:** `lib/ble/code_rotator.dart:rotateCode` & `backend/app/routers/checkin_stub.py:check_in`
- **Existing Behavior:** The backend check-in endpoint verified `sha256(payload.ephemeral_nonce) == session.secret_hash`. However, `session.secret_hash` was a static hash generated when the faculty started the session in PostgreSQL, whereas the mobile broadcaster rotated an 8-hex character code every 15-30 seconds.
- **Exploitation Scenario:** If the rotating beacon code differs from the static secret hash stored at session creation, student check-ins via the backend fail. If student submits the static hash, the rotation mechanism is completely bypassed.
- **Root Cause:** Decoupling between server-side session secrets and real-time rotating broadcast challenges.
- **Recommended Correction:** Implement server-synchronized challenge distribution or time-based OTP / HMAC challenge protocol where `challenge = HMAC-SHA256(session_secret, time_window)`. Both faculty broadcaster and backend verifier evaluate the challenge against valid rotation windows ($t$ and $t-1$).
- **Test Required:** Integration test confirming that challenges generated by the rotation algorithm are verified by the backend within the active window and rejected once window expires.
- **Final Status:** IN PROGRESS (Phase 3 & 5 Remediation)

---

### 4. SEC-03: Lack of Hardware-Backed Device Attestation
- **Issue ID:** `SEC-03`
- **Severity:** `HIGH`
- **File & Function:** `lib/ble/device_binding_service.dart:getOrCreateDeviceId`
- **Existing Behavior:** Device binding relies on a randomly generated UUID string stored in `flutter_secure_storage`.
- **Exploitation Scenario:** A student can export or transfer their device UUID or run multiple app instances on a rooted emulator, enabling one device to impersonate several students simultaneously ("proxy check-in").
- **Root Cause:** Absence of hardware-backed asymmetric key generation and attestation.
- **Recommended Correction:** Implement asymmetric keypair generation using platform secure hardware (Android Keystore / iOS Keychain). The private key never leaves secure storage; the public key is registered with FastAPI at `/api/v1/devices/register`. Attendance payloads must be signed by the private key.
- **Test Required:** Automated tests verifying that keypairs are generated, registered, and validated on check-in, and that unregistered or revoked public keys are rejected.
- **Final Status:** IN PROGRESS (Phase 4 Remediation)

---

### 5. AUTH-01: Insecure Direct Object Reference (IDOR) on Session Termination
- **Issue ID:** `AUTH-01`
- **Severity:** `CRITICAL`
- **File & Function:** `backend/app/routers/sessions.py:stop_session`
- **Existing Behavior:** Any user with the `faculty` role could submit `POST /api/v1/sessions/{id}/stop` for any session ID in the institution, immediately closing another instructor's active session.
- **Exploitation Scenario:** Faculty Member A terminates Faculty Member B's ongoing lecture attendance session, disrupting class records.
- **Root Cause:** Missing resource ownership verification (`sess.started_by == user_record.id`).
- **Recommended Correction:** Verify that `current_user.role == 'admin'` or `sess.started_by == user_record.id`. Return `HTTP 403 Forbidden` on mismatch.
- **Test Required:** Pytest verifying unauthorized faculty cannot stop foreign sessions.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test_audit_regressions.py`)

---

### 6. AUTH-02: Course Roster Cross-Faculty Modification IDOR
- **Issue ID:** `AUTH-02`
- **Severity:** `CRITICAL`
- **File & Function:** `backend/app/routers/roster.py:import_course_roster`
- **Existing Behavior:** Any authenticated faculty could upload a student CSV roster to any `course_id`, regardless of course ownership.
- **Exploitation Scenario:** Faculty A overwrites or injects students into Faculty B's course roster.
- **Root Cause:** Missing course ownership check against authenticated faculty user ID.
- **Recommended Correction:** Query `Course` where `id == course_id`. Enforce `course.faculty_id == user_record.id` or `current_user.role == 'admin'`. Return `HTTP 403 Forbidden` if unauthorized.
- **Test Required:** Pytest verifying non-owner faculty cannot upload roster CSV.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test_roster_security.py`)

---

### 7. AUTH-03: Admin Self-Approval & Role Synchronization Desynchronization
- **Issue ID:** `AUTH-03`
- **Severity:** `HIGH`
- **File & Function:** `backend/app/routers/admin.py:approve_user`
- **Existing Behavior:** An administrator could approve/escalate their own user profile, and if Firebase Authentication claim stamping failed, the database state committed anyway, resulting in permanent desync between PostgreSQL and Firebase JWT claims.
- **Exploitation Scenario:** Admin demotion/approval inconsistencies lead to privilege escalation or bypass of backend authorization checks.
- **Root Cause:** Lack of self-modification check and unhandled external provider synchronization failure.
- **Recommended Correction:** Reject self-approval (`uid == current_admin.uid`). Raise HTTP 502 Bad Gateway in production if Firebase custom claim stamping fails, preventing uncommitted authorization desynchronization.
- **Test Required:** Pytest verifying admin cannot approve self and that claim failure triggers rollback.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test_rbac_negative.py`)

---

### 8. RULE-01: Firestore Rotation Window Freshness Unbounded
- **Issue ID:** `RULE-01`
- **Severity:** `HIGH`
- **File & Function:** `firestore.rules:isValidAttendanceCreate`
- **Existing Behavior:** `prevCode` validation did not bound freshness against `live.rotatedAt`, allowing previous rotation codes to be accepted indefinitely if a session stalled.
- **Exploitation Scenario:** If faculty broadcaster crashes or pauses, previously leaked codes could be redeemed minutes or hours later.
- **Root Cause:** Missing time window bound on `prevCode`.
- **Recommended Correction:** Enforce `request.time <= live.rotatedAt + duration.value(45, 's')` on both `current.code` and `prevCode`.
- **Test Required:** Firestore emulator security rules tests asserting rejection of codes older than 45 seconds.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `firestore-tests`)

---

### 9. BLE-01: Broadcaster Periodic Timer Concurrency Race Condition
- **Issue ID:** `BLE-01`
- **Severity:** `HIGH`
- **File & Function:** `lib/ble/code_rotator.dart:startRotation`
- **Existing Behavior:** Repeated calls to `startRotation` created multiple overlapping periodic timers without cancelling prior instances, and async rotation ticks could interleave.
- **Exploitation Scenario:** High frequency advertising restarts caused peripheral BLE crash on Android/iOS and corrupted rotation logs.
- **Root Cause:** Lack of rotation reentrancy guard (`_isRotating` mutex) and timer cancellation.
- **Recommended Correction:** Cancel existing `_timer` on start; guard async tick with `if (_isRotating) return; try { _isRotating = true; ... } finally { _isRotating = false; }`.
- **Test Required:** Flutter unit test asserting timer cancellation and single concurrent rotation.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test/unit/ble_test.dart`)

---

### 10. BLE-02: Silent Scanner Stream Error Swallowing
- **Issue ID:** `BLE-02`
- **Severity:** `MEDIUM`
- **File & Function:** `lib/ble/flutter_blue_plus_scanner.dart:watch`
- **Existing Behavior:** `scanResults.listen` provided `onError: (_) {}`, silently dropping adapter errors and hardware crashes.
- **Exploitation Scenario:** Scanner hangs indefinitely with no feedback to the student when Bluetooth adapter restarts.
- **Root Cause:** Swallowed stream exceptions.
- **Recommended Correction:** Forward stream errors to output stream controller via `controller.addError(err)`.
- **Test Required:** Flutter unit test verifying error propagation.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test/unit/ble_test.dart`)

---

### 11. BLE-03: False CodeRejectedFailure on Duplicate Check-In
- **Issue ID:** `BLE-03`
- **Severity:** `MEDIUM`
- **File & Function:** `lib/ble/student_checkin_controller.dart:executeCheckIn`
- **Existing Behavior:** When a student who was already marked present submitted again, Firestore returned `permission-denied` (due to create-only rules). The controller caught this and falsely reported `CodeRejectedFailure`.
- **Exploitation Scenario:** Confused students repeatedly attempt check-in believing their code was rejected when they are already marked present.
- **Root Cause:** Inability to distinguish duplicate check-in permission denial from invalid code rejection.
- **Recommended Correction:** Read existing attendance record upon permission denial; if record exists, emit `CheckInSuccess` with existing timestamp.
- **Test Required:** Unit test simulating duplicate submission recovering existing state.
- **Final Status:** FIXED AND VERIFIED (Commit `20252ea`, verified by `test/unit/ble_test.dart`)

---

## Remediation Roadmap & Execution Matrix

| Phase | Description | Target Files | Status |
|:---:|:---|:---|:---:|
| **Phase 1** | Complete Architecture Audit | `docs/PRODUCTION_READINESS_AUDIT.md` | **COMPLETED** |
| **Phase 2** | One Source of Truth (PostgreSQL Authority) | `lib/ble/student_checkin_controller.dart`, `backend/scripts/reconcile_attendance.py` | **IN PROGRESS** |
| **Phase 3** | Rebuild BLE Challenge Security Protocol | `backend/app/services/challenge_service.py`, `lib/ble/code_rotator.dart` | **IN PROGRESS** |
| **Phase 4** | Hardware Device Authentication | `backend/app/routers/devices.py`, `backend/app/services/device_service.py`, `lib/services/device_auth_service.dart` | **PENDING** |
| **Phase 5** | Production Backend Check-In Engine | `backend/app/routers/checkin.py`, `backend/app/services/attendance_service.py` | **PENDING** |
| **Phase 6** | Admin & Authorization Hardening | `backend/app/routers/admin.py`, `backend/app/routers/sessions.py` | **VERIFIED** |
| **Phase 7** | PostgreSQL Schema Integrity & Uniqueness | `backend/app/models/`, Alembic migrations | **PENDING** |
| **Phase 8** | Zero-Trust Firestore Security Rules | `firestore.rules`, `firestore-tests/` | **VERIFIED** |
| **Phase 9** | Flutter Application Integration | `lib/ble/student_checkin_controller.dart`, Riverpod providers | **PENDING** |
| **Phase 10** | UI & User Experience Refinement | `lib/screens/` | **PENDING** |
| **Phase 11** | End-to-End Automated Testing Suite | `backend/tests/`, `test/` | **PENDING** |
| **Phase 12** | Real Device Testing Specification | `docs/REAL_DEVICE_TESTING.md` | **PENDING** |
| **Phase 13** | CI/CD Pipeline & Release Verification | `.github/workflows/ci.yml` | **VERIFIED** |
| **Phase 14** | Performance & Distributed Idempotency | Connection pooling, retry policies | **PENDING** |
| **Phase 15** | Final Security Audit & Deployment Guide | `docs/FINAL_SECURITY_AUDIT.md`, `docs/END_TO_END_TEST_REPORT.md` | **PENDING** |
