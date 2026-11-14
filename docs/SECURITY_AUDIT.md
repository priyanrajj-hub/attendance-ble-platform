# SECURITY AUDIT & VULNERABILITY REMEDIATION MATRIX
**Amrita BLE Proximity Attendance Platform**  
*Audit Scope:* End-to-End Cryptographic Attendance & Zero-Trust Protocol  

---

## 1. Vulnerability Remediation Matrix

| Finding ID | Severity | Root Cause in Legacy Code | Engineering Remediation in Current Head | Verification Evidence |
|---|---|---|---|---|
| **SEC-01** | **CRITICAL** | Student direct write allowed in Firestore `attendance/{uid}` | Set `allow write: if false;` on client SDKs. All writes must route through FastAPI PostgreSQL ACID transactions with Admin SDK projection. | `test_rbac_negative.py`, `rules.spec.js` Suites 8 & 9 |
| **SEC-02** | **CRITICAL** | Client-submitted RSSI trusted without server validation | Server compares observed RSSI against `sess.rssi_threshold` (e.g. $\ge -75\text{ dBm}$) and validates physical sanity bounds ($-120 \le \text{RSSI} \le 0$). Rejects weak or out-of-range signals. | `test_weak_rssi_below_threshold_rejected`, `test_invalid_rssi_range_rejected` |
| **SEC-03** | **HIGH** | `ephemeral_token` / `secret_hash` leaked on public session queries | Excluded `secret_hash` from all public and student Pydantic response models. Returned strictly on `POST /sessions/start` to initiating faculty. | `test_sec03_no_student_endpoint_returns_session_secret` |
| **SEC-04** | **HIGH** | Optional client signatures allowed forged proxy check-ins | Mandated hardware-backed cryptographic signatures in `attendance_service.py` (`HTTP 400` if missing, `HTTP 403` if forged). | `test_missing_device_signature_rejected`, `test_forged_device_signature_rejected` |
| **SEC-05** | **HIGH** | Stale / replay rotating codes accepted across multiple students | Challenges synchronized to Unix epoch steps ($W=20s$) with $\pm 1$ step drift allowance. Added `consumed_nonces` table with unique constraint on `(session_id, signature_hash)` and `(session_id, student_id, nonce)`. | `test_expired_rotating_code_rejected`, `test_future_client_timestamp_rejected` |
| **SEC-06** | **MEDIUM** | Faculty session creation without PostgreSQL backend session ID | Unified session creation: FastAPI starts session first, returns `backendSessionId`, Flutter uses it for Firestore projection and rotation. | `faculty_session_screen.dart` |
| **SEC-07** | **HIGH** | Device attestation status falsely claimed "verified" on simple public key registration | Created explicit two-tier model: default is `"key_registered"` (asymmetric software key enrolled). Remote hardware attestation requires verified X.509 Android Key Attestation certificate chain or Play Integrity token via `POST /api/v1/devices/attestation-challenge` to elevate to `"hardware_attested"`. | `devices.py`, `test_device_attestation_challenge_and_verification` |
| **SEC-08** | **HIGH** | Manual override audit trail missing in PostgreSQL; concurrency race on duplicate submission | Added `override_reason` and `marked_by` columns to `attendance_records`, added `Override` entries in `overrides` table, logged security events in `audit_log`, and wrapped transaction in nested rollback savepoint for idempotent race resolution. | `test_manual_override_audit_trail_persisted_in_postgresql`, `test_faculty_manual_override_unauthorized_for_other_faculty` |

---

## 2. Inherent Physical Limitations of RSSI & BLE Proximity

> [!WARNING]
> While server-side RSSI enforcement rejects client-reported values weaker than the classroom threshold, RSSI remains a **client-reported metric** in BLE peripheral-observer topologies.

1. **Client Spoofing Vulnerability**: A modified client application running on a rooted device could falsely report `-60 dBm` even if the actual radio packet had an RSSI of `-85 dBm` or was received via a relay attack.
2. **Physical Multipath & Human Attenuation**: Human bodies attenuate 2.4 GHz RF signals by approximately $3 \text{ to } 10\text{ dBm}$. A student seated behind a crowded lecture row may register a lower RSSI than an absent student standing outside the door with direct line of sight.
3. **Mitigations & Defense-in-Depth**:
   - Short 20-second rotation window with synchronized HMAC-SHA256 nonces prevents delayed re-broadcasting.
   - Per-student signature binding and unique device enrollment prevent credential sharing.
   - For high-stakes examinations, faculty manual confirmation or two-way BLE challenge-response is required.
