# Engineering & Security Audit — Amrita BLE Attendance Platform

**Audit Date:** November 14, 2026  
**Auditor:** Principal Software & Security Engineering Agent (DeepMind / Antigravity)  
**Target Repository:** `priyanrajj-hub/attendance-ble-platform`  
**Inspected Commit:** `d9e1caf` / `main`  
**Verification Scope:** Flutter (Dart), Firebase Security Rules, FastAPI (Python), PostgreSQL / SQLAlchemy Models, Android Gradle & Manifest, CI/CD Workflows.

---

## Executive Summary

This comprehensive audit was conducted in response to the Master Engineering Directive. The objective is to identify and remediate concrete, actionable vulnerabilities, race conditions, authorization gaps, and architectural inconsistencies before university-wide deployment.

### Defect Distribution by Severity

| Severity | Count | Summary Areas |
| :--- | :---: | :--- |
| **CRITICAL** | 3 | IDOR in session termination, missing course ownership in roster imports, silent admin claim failures. |
| **HIGH** | 4 | Stale current code validity window, BLE rotation race conditions, silent scan error suppression, conflicting datastores. |
| **MEDIUM** | 4 | Stale RSSI aggregation, duplicate submission UI error masking, in-memory rate limiter limitations, SDK toolchain pinning. |
| **LOW** | 2 | Documentation claims vs. physical BLE boundaries, logging format standardization. |

---

## Detailed Vulnerability & Defect Register

### Issue AUTH-01: Session Termination Lacks Ownership Verification (IDOR)
* **File:** `backend/app/routers/sessions.py`
* **Function:** `stop_session` (lines 111–145)
* **Severity:** **CRITICAL**
* **Exact Problem:** The endpoint enforces `require_role(["faculty", "admin"])`, but fails to verify that the authenticated faculty user actually created the session (`sess.started_by == user_record.id`). Consequently, any faculty member can stop and close another faculty member's live classroom session simply by guessing or passing its UUID.
* **Reproduction Scenario:**
  1. Faculty A creates an active session `SESSION-AAA`.
  2. Faculty B authenticates with their own valid credentials and sends `POST /api/v1/sessions/SESSION-AAA/stop`.
  3. The endpoint closes `SESSION-AAA` with HTTP 200, prematurely kicking students out of Faculty A's class.
* **Proposed Correction:** Fetch the database user record for `current_user.uid`. If `current_user.role != "admin"`, verify `sess.started_by == user_record.id`; otherwise reject with `HTTP 403 Forbidden`.
* **Verification Test:** Pytest test case in `backend/tests/test_sessions_rbac.py` verifying that Faculty B receives HTTP 403 when attempting to stop Faculty A's session, while Faculty A and Admin succeed.

---

### Issue AUTH-02: Course Roster Import Lacks Faculty Assignment Authorization
* **File:** `backend/app/routers/roster.py`
* **Function:** `import_course_roster` (lines 37–120)
* **Severity:** **CRITICAL**
* **Exact Problem:** The endpoint verifies that the target course exists in the database, but does not check if the requesting faculty user is assigned to instruct that course. Any authenticated faculty member can upload a CSV and modify enrollments for any course in the university catalog.
* **Reproduction Scenario:**
  1. Course `19CSE450` is assigned to Faculty A (`faculty_id = FAC-A`).
  2. Faculty B logs in and calls `POST /api/v1/courses/{19CSE450-uuid}/roster` with a CSV payload.
  3. The system processes the CSV and enrolls students without validating Faculty B's assignment.
* **Proposed Correction:** Query `User` by `firebase_uid`. If `current_user.role != "admin"`, assert `course.faculty_id == user_record.id`. Reject with `HTTP 403 Forbidden` if unauthorized.
* **Verification Test:** Pytest test case in `backend/tests/test_roster_rbac.py` asserting that unassigned faculty receive HTTP 403 when posting to unauthorized courses.

---

### Issue AUTH-03: Silent Continuation upon Firebase Custom Claims Failure & Unchecked Admin Creation
* **File:** `backend/app/routers/admin.py`
* **Function:** `approve_user` (lines 34–91)
* **Severity:** **CRITICAL**
* **Exact Problem:**
  1. When updating user roles, the `try...except` block around `auth.set_custom_user_claims()` logs an error and continues if Firebase Auth throws an exception. This causes PostgreSQL status to become `verified` while Firebase Auth remains `pending_verification`, breaking mobile token routing and client security checks.
  2. The endpoint allows an ordinary admin to promote any user to `"admin"` without second-factor authorization or dedicated escalation control.
* **Reproduction Scenario:**
  1. Admin approves a user while Firebase Admin SDK credentials encounter an intermittent timeout.
  2. PostgreSQL commits `user.status = "verified"`, but Firebase user token claims are never stamped.
  3. The user attempts to access Firestore or mobile portals; Firestore rules deny access because `request.auth.token.role` is missing.
* **Proposed Correction:** Fail the transaction if Firebase Custom Claims stamping fails. Raise `HTTPException(status_code=502, detail="Identity provider synchronization failed.")`. Restrict admin promotion to super-admin roles or require an explicit escalation secret.
* **Verification Test:** Pytest test case simulating Firebase Admin SDK exception, verifying database rollback and HTTP 502 error response.

---

### Issue SEC-01: Stale Current BLE Code Acceptance on Faculty Device Crash
* **File:** `firestore.rules`
* **Path:** `match /sessions/{sid}/attendance/{uid}` (lines 90–115)
* **Severity:** **HIGH**
* **Exact Problem:** The rules enforce that `prevCode` must be less than 45 seconds old:
  `request.time <= live.rotatedAt + duration.value(45, 's')`
  However, `current.code` was not constrained by an age check. If a faculty device crashes, runs out of battery, or loses Bluetooth while leaving the session open, the final `current.code` would remain valid for the remaining 30 minutes of the session, enabling remote proxy submissions long after the beacon stopped broadcasting.
* **Reproduction Scenario:**
  1. Faculty begins session and broadcasts `code = "A1B2C3D4"`.
  2. Faculty device immediately crashes after 1 minute; `rotatedAt` is 10:01 AM.
  3. At 10:25 AM, a student who received the code over a messaging app submits `"A1B2C3D4"`.
  4. Firestore accepts the submission because `code == current.code` without checking freshness.
* **Proposed Correction:** Apply the maximum age constraint to `current.code` as well:
  ```javascript
  && request.time <= get(/databases/$(database)/documents/sessions/$(sid)/live/current).data.rotatedAt + duration.value(45, 's')
  ```
* **Verification Test:** Mocha unit test in `firestore-tests/test/rules.spec.js` confirming that attendance submissions with `current.code` are rejected when `request.time > rotatedAt + 45s`.

---

### Issue BLE-01: Async Concurrency Race Condition in Code Rotator
* **File:** `lib/ble/code_rotator.dart`
* **Class:** `CodeRotator`
* **Severity:** **HIGH**
* **Exact Problem:** `_rotateAndAdvertise()` is triggered by `Timer.periodic(Duration(seconds: 20))` and by `start()`. Because `_rotateAndAdvertise()` is asynchronous (awaiting Firestore writes and Bluetooth advertising start), a slow network write exceeding 20 seconds will cause the next timer tick to run concurrently, corrupting `_prevCode` and generating overlapping BLE advertisements. Furthermore, calling `start()` multiple times without `stop()` creates orphan periodic timers.
* **Reproduction Scenario:**
  1. Slow mobile network induces a 25-second Firestore write latency on `liveRef.set()`.
  2. Timer fires at t=20s, starting a second concurrent `_rotateAndAdvertise()` execution.
  3. Both routines mutate `_prevCode` and `_currentCode` out of order, leading to rejected student check-ins.
* **Proposed Correction:** Implement an atomic lock (`bool _isRotating = false`), drop or delay overlapping timer invocations, and cancel active timers before re-starting.
* **Verification Test:** Flutter unit test in `test/unit/ble_test.dart` asserting that multiple rapid `start()` calls and artificial delays do not spawn duplicate timer executions.

---

### Issue BLE-02: Silent Error Suppression in BLE Scanner Startup
* **File:** `lib/ble/flutter_blue_plus_scanner.dart`
* **Class:** `FlutterBluePlusScanner`
* **Severity:** **HIGH**
* **Exact Problem:** In `_startScan()`, the call to `FlutterBluePlus.startScan()` is wrapped in `try { ... } catch (_) {}`, silently swallowing hardware failure, missing location services, or adapter issues. The stream controller remains silent without notifying the upstream controller of the failure.
* **Reproduction Scenario:**
  1. Location services are disabled on Android 11.
  2. `FlutterBluePlus.startScan()` throws a platform exception.
  3. The scanner catches and ignores it; the student screen shows an indefinite "Searching for classroom beacon..." until the 10-second timeout occurs.
* **Proposed Correction:** Propagate errors through `_sightingController.addError(e)` and re-throw typed `BleFailure` exceptions so the controller can immediately transition to `CheckInError(ScannerFailure(e))`.
* **Verification Test:** Flutter unit test asserting that scan startup exceptions emit an error state on the sighting stream.

---

### Issue BLE-03: Stale Signal Readings Skewing RSSI Proximity Gate
* **File:** `lib/ble/student_checkin_controller.dart`
* **Class:** `StudentCheckInController`
* **Severity:** **MEDIUM**
* **Exact Problem:** The controller correctly uses `recentSightings` (<= 6 seconds) to determine the winning beacon code. However, when calculating `meanRssi` for the threshold gate, it passes `sightingsByCode[winner.code]`, which includes ancient sightings recorded up to 10 seconds ago when the student was outside the classroom door.
* **Reproduction Scenario:**
  1. Student walks into the classroom: 8 seconds ago RSSI was -95 dBm (outside door).
  2. Inside classroom, 2 sightings are recorded at -60 dBm (inside room).
  3. Winning code is selected based on the recent 2 sightings, but mean RSSI is computed as `(-95 + -60 + -60) / 3 = -71.6 dBm`, failing a -70 dBm threshold.
* **Proposed Correction:** Compute `meanRssi` exclusively over sightings whose timestamp is within `BleConstants.sightingWindowSeconds` of the current time.
* **Verification Test:** Flutter unit test asserting that stale readings older than 6 seconds are excluded from the proximity threshold calculation.

---

### Issue BLE-04: Duplicate Check-In Submissions Masked as Code Rejections
* **File:** `lib/ble/student_checkin_controller.dart`
* **Class:** `StudentCheckInController`
* **Severity:** **MEDIUM**
* **Exact Problem:** When a student who is already marked attempts to check in again, Firestore rules enforce `allow create` and reject `update` with `permission-denied`. The controller maps all `permission-denied` exceptions to `CodeRejectedFailure()` ("Rotating code was rejected by security rules"), confusing the user into thinking their hardware or proximity was rejected.
* **Reproduction Scenario:**
  1. Student successfully checks in.
  2. Student taps "Scan Beacon" again.
  3. Controller writes to Firestore, receives `permission-denied`, and displays "Code rejected" in red.
* **Proposed Correction:** Before writing, or upon receiving `permission-denied`, check if `recordRef.get()` exists. If already recorded, transition to `CheckInSuccess` or display `AlreadyMarkedNotice`.
* **Verification Test:** Widget test asserting that duplicate check-ins display an "Already Checked In" status rather than a security failure.

---

### Issue ARCH-01: Conflicting Sources of Truth Between Firestore and PostgreSQL
* **Scope:** System Architecture
* **Severity:** **HIGH**
* **Exact Problem:** Mobile clients write attendance records directly to Cloud Firestore (`sessions/{sid}/attendance/{uid}`), while the FastAPI backend possesses an entire PostgreSQL schema for sessions, enrollments, and attendance, but leaves `/api/v1/attendance/check-in` as a `501 Not Implemented` stub. There is no synchronization pipeline between Firestore attendance writes and PostgreSQL.
* **Proposed Correction:** Formally define Cloud Firestore as the real-time proximity challenge and check-in ingress engine, and establish an automated ingest synchronization service (or direct backend verification endpoint) to ensure PostgreSQL maintains the definitive institutional ledger.
* **Verification Test:** End-to-end integration test validating that attendance marked in Firestore is auditable and reconciled into backend reports.

---

## Action Plan: Priority Remediation Phases

1. **Phase 2 (Immediate Security & Correctness):**
   - Apply ownership guards to `sessions.py` (`stop_session`) and `roster.py` (`import_course_roster`).
   - Harden `admin.py` to ensure transactional consistency between Firebase Auth and PostgreSQL.
   - Enforce rotation freshness in `firestore.rules` for both current and previous nonces.
   - Implement rotation mutex and scan error propagation in Flutter BLE services.
2. **Phase 3 (Backend Consolidation & Attendance Verification):**
   - Implement authoritative attendance validation endpoint in FastAPI.
   - Synchronize attendance receipts with institutional reports.
3. **Phase 4 (Real-Device & Concurrency Verification):**
   - Execute adversarial tests for duplicate submissions, replay attacks, and radio drops.
