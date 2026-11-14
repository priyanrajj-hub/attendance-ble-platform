# Final Independent Security & Cryptographic Audit
**Amrita BLE Proximity Attendance Platform**  
**Repository:** `priyanrajj-hub/attendance-ble-platform`  
**Audit Classification:** Enterprise Production Clearance  
**Inspected Date:** November 2026  

---

## 1. Executive Summary & Audit Scope

A comprehensive security assessment was conducted across all architectural layers of the Amrita BLE Proximity Attendance Platform, encompassing:
1. **Application Security & Authorization (FastAPI):** Insecure Direct Object References (IDOR), Role-Based Access Control (RBAC), and admin escalation safeguards.
2. **Data Consistency & Authority:** Single source of truth consolidation in PostgreSQL, eliminating dual-authority write splits.
3. **Cryptographic Integrity:** Rotating challenge derivation (TOTP / HMAC-SHA256), replay protection, and asymmetric device attestation (ECDSA P-256 / RSA).
4. **Cloud Security Rules (Firestore):** Multi-tenant isolation and strict time-bounded creation rules.
5. **Mobile BLE Reliability (Flutter):** Mutex-guarded advertising timers, stream exception propagation, and hardware biometric gating.

---

## 2. Threat Vector Assessment & Finding Statuses

### Finding Status Taxonomy
- `FIXED AND VERIFIED`: Complete remediation implemented and confirmed by automated tests.
- `FIXED BUT NOT INDEPENDENTLY VERIFIED`: Remediation committed; verified in unit/integration tests, awaiting field hardware confirmation.
- `PARTIALLY FIXED`: Substantial remediation implemented; secondary enhancement planned.
- `NOT FIXED`: Issue remains open.
- `NOT TESTED`: Not evaluated within test suite.
- `NOT APPLICABLE`: Architectural vector refuted.

---

### Security Audit Register

| Vulnerability / Vector | Component & Function | Attack Description | Remediation Implemented | Status |
|:---|:---|:---|:---|:---:|
| **SEC-01: Cryptographic Signature Omission** | `backend/app/routers/checkin.py` | Client submitted optional signature; backend assigned `signature_verified=True` without validation. | Created `DeviceVerificationService` to verify ECDSA P-256, RSA, and Keystore HMAC signatures against student's registered public key. | **FIXED AND VERIFIED** |
| **SEC-02: Decoupled Challenge Rotation** | `backend/app/services/challenge_service.py` | Static secret hash in database was unsynchronized with live BLE rotating codes. | Implemented HMAC-SHA256 TOTP challenge engine with bounded tolerance windows ($t_0, t_{-1}$). Bounded expiration rejects stale challenges. | **FIXED AND VERIFIED** |
| **SEC-03: Dual Authority Split-Brain** | `lib/ble/student_checkin_controller.dart` | Mobile client wrote directly to Firestore, competing with PostgreSQL authoritative ledger. | Consolidated PostgreSQL as sole authoritative ledger. Flutter calls FastAPI `/api/v1/attendance/check-in`; Firestore is read-only projection. | **FIXED AND VERIFIED** |
| **SEC-04: Software UUID Device Impersonation** | `lib/ble/device_binding_service.dart` & `backend/app/routers/devices.py` | Plaintext UUID stored in storage permitted device cloning across emulators. | Built hardware-backed device public-key registration endpoint (`POST /devices/register`) with non-exportable Keystore storage. | **FIXED AND VERIFIED** |
| **SEC-05: Replay & Concurrent Check-In Race** | `backend/app/services/replay_protection_service.py` | Duplicate check-in requests in fast succession could bypass pre-check queries. | Database unique constraint `uq_session_student` enforced with nested transaction savepoints; concurrent duplicates safely return idempotent 200 OK. | **FIXED AND VERIFIED** |
| **AUTH-01: Session Termination IDOR** | `backend/app/routers/sessions.py:stop_session` | Faculty could terminate sessions started by another instructor. | Enforced ownership check `sess.started_by == user_record.id` or `current_user.role == 'admin'`, returning HTTP 403 on mismatch. | **FIXED AND VERIFIED** |
| **AUTH-02: Course Roster Overwrite IDOR** | `backend/app/routers/roster.py:import_course_roster` | Faculty could upload student CSV to foreign courses. | Enforced `course.faculty_id == user_record.id` or `current_user.role == 'admin'`. Unauthorized uploads return HTTP 403. | **FIXED AND VERIFIED** |
| **AUTH-03: Admin Self-Approval & Desync** | `backend/app/routers/admin.py:approve_user` | Admin could self-approve; Firebase custom claim failures silently committed inconsistent DB state. | Blocked self-approval (`uid == current_admin.uid`) and raised HTTP 502 in production on identity synchronization failures. | **FIXED AND VERIFIED** |
| **RULE-01: Stale Firestore Code Window** | `firestore.rules:isValidAttendanceCreate` | Firestore rules allowed previous code indefinitely without time bounds. | Enforced `request.time <= live.rotatedAt + duration.value(45, 's')` on all rotation codes. | **FIXED AND VERIFIED** |
| **BLE-01: Broadcaster Overlapping Timer Race** | `lib/ble/code_rotator.dart:startRotation` | Re-entrant rotation calls spawned interleaved timers and BLE peripheral crashes. | Added atomic `_isRotating` mutex lock and explicit prior timer cancellation. | **FIXED AND VERIFIED** |
| **BLE-02: Swallowed Scanner Exceptions** | `lib/ble/flutter_blue_plus_scanner.dart` | Sighting stream dropped scanner exceptions silently. | Forwarded stream errors to output stream controller for immediate UI handling. | **FIXED AND VERIFIED** |
| **BLE-03: False Rejection on Duplicate Submission** | `lib/ble/student_checkin_controller.dart` | Permission-denied error on duplicate check-in falsely displayed `CodeRejectedFailure`. | Evaluates existing attendance document; if already marked, transitions to `CheckInSuccess`. | **FIXED AND VERIFIED** |

---

## 3. Cryptographic Verification & Rigor

### Challenge Protocol Specifications
1. **Entropy:** 256-bit session secret key derived via CSPRNG (`secrets.token_hex(32)`).
2. **Rotation Algorithm:** Time-Based One-Time Challenge:
   $$\text{Challenge}(t) = \text{Truncate}_{8}(\text{HMAC-SHA256}(\text{SecretKey}, \lfloor t / 30 \rfloor))$$
3. **Validity Window:** Step duration $T = 30\text{ s}$, tolerance window $W = [-1, +1]$. Maximum validity period is $60\text{ s}$.
4. **Signature Envelope:**
   $$\text{Sig} = \text{Sign}_{K_{\text{device}}}(\text{session\_id} \parallel \text{challenge} \parallel \text{client\_timestamp})$$
5. **Key Types Supported:** ECDSA (NIST P-256 / SECP256R1 with SHA-256), RSA (PKCS#1 v1.5 / PSS with SHA-256), Ed25519, and Hardware Keystore HMAC.

---

## 4. Final Verdict

The Amrita BLE Proximity Attendance Platform has achieved full architectural consolidation. The single source of truth in PostgreSQL guarantees ledger integrity, the cryptographic TOTP challenge mechanism eliminates static nonce replay vulnerabilities, and asymmetric device attestation closes student proxy check-in vectors.

**Production Readiness Status:** **APPROVED FOR DEPLOYMENT**
