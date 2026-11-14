# SECURITY AUDIT & VULNERABILITY REMEDIATION MATRIX
**Amrita BLE Proximity Attendance Platform**  
*Audit Scope:* End-to-End Cryptographic Attendance & Zero-Trust Protocol  

---

## 1. Vulnerability Remediation Matrix

| Finding ID | Severity | Root Cause in Legacy Code | Engineering Remediation in Commit `3a551bf` & Head | Verification Evidence |
|---|---|---|---|---|
| **SEC-01** | **CRITICAL** | Student direct write allowed in Firestore `attendance/{uid}` | Set `allow write: if false;` on client SDKs. All writes must route through FastAPI PostgreSQL ACID transactions with Admin SDK projection. | `test_rbac_negative.py`, `rules.spec.js` Suite 8 & 9. |
| **SEC-02** | **CRITICAL** | Client-submitted RSSI trusted without server validation | FastAPI verifies observed RSSI against session configured threshold. Backend rejects weak signals outside proximity boundary. | `test_attendance_e2e.py` |
| **SEC-03** | **HIGH** | `ephemeral_token` / `secret_hash` leaked on public session queries | Excluded `secret_hash` from all public and student Pydantic response models. Returned strictly on `POST /sessions/start` to initiating faculty. | `test_sec03_no_student_endpoint_returns_session_secret` |
| **SEC-04** | **HIGH** | Optional client signatures allowed forged proxy check-ins | Mandated hardware-backed cryptographic signatures in `attendance_service.py` (`HTTP 400` if missing, `HTTP 403` if invalid). | `test_missing_device_signature_rejected`, `test_forged_device_signature_rejected` |
| **SEC-05** | **HIGH** | Stale / replay rotating codes accepted across multiple students | Ephemeral challenges synchronized to server epoch steps ($W=20s$) with strict 1-step grace drift. Per-student unique attendance constraint enforced. | `test_expired_rotating_code_rejected`, `test_challenge_crypto_vectors.py` |
| **SEC-06** | **MEDIUM** | Faculty session creation without PostgreSQL backend session ID | Unified session creation: FastAPI starts session first, returns `backendSessionId`, Flutter uses it for Firestore projection and rotation. | `faculty_session_screen.dart` |
| **SEC-07** | **MEDIUM** | Device attestation status falsely marked "verified" on simple key import | Changed initial registration status to `"key_registered"`. Status `"hardware_verified"` reserved for remote certificate chains. | `devices.py`, `test_device_registration_and_signature_e2e` |
| **SEC-08** | **MEDIUM** | Direct client manual override writes allowed in Firestore | Added authoritative backend route `POST /sessions/{id}/manual-override` with course ownership and reason validation. | `test_faculty_manual_override_success` |

---

## 2. Cryptographic Security Standards

1. **Classroom Challenge Derivation**:
   $$\text{Challenge} = \text{Truncate}_{128}\left(\text{HMAC-SHA256}(\text{Key}=\text{SessionSecret}, \text{Msg}=\text{SessionID} \parallel \text{EpochStep})\right)$$
   - Rotation Interval: 20 seconds.
   - Drift Window: $\pm 1$ step (maximum $\pm 20$ seconds drift tolerance).

2. **Device Authentication**:
   - Asymmetric key generation inside Android Keystore / iOS Secure Enclave.
   - Signature algorithm: ECDSA P-256 with SHA-256 (or RSA-PSS 2048-bit fallback).
   - Signed message: `"${session_id}:${ephemeral_nonce}:${client_timestamp}"`.
