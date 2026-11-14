# MASTER ENGINEERING AUDIT & PRODUCTION SPECIFICATION
**Amrita BLE Proximity Attendance Platform**  
*Repository:* `priyanrajj-hub/attendance-ble-platform`  
*Target Environment:* Production Enterprise University Deployment  
*Author:* Principal Software Architect & Principal Security Engineer  

---

## 1. System Architecture & Entry Points

```
+-----------------------------------------------------------------------------------+
|                                  FLUTTER CLIENT                                   |
|                                                                                   |
|  [Student Check-In]                             [Faculty Session Console]         |
|  - BLE Scanner (128-bit Service UUID)           - BLE Broadcaster (HMAC Nonce)   |
|  - Android Keystore / iOS Keychain Signature    - Synchronized Epoch Rotator      |
|  - Mandatory Auth Bearer Token                  - Authoritative Manual Override   |
+--------------------------+---------------------------------+----------------------+
                           |                                 |
              Proximity Check-In / Device Reg       Session Start / Override
              (HTTPS JSON REST Payload)             (HTTPS JSON REST Payload)
                           |                                 |
                           v                                 v
+-----------------------------------------------------------------------------------+
|                           FASTAPI APPLICATION SERVER                              |
|                                                                                   |
|  [Security Middlewares]                                                           |
|  - TrustedHostMiddleware, ContentSecurityPolicy, StrictTransportSecurity          |
|  - Role-Based Access Control (RBAC): Admin, Faculty, Student (Domain Checked)     |
|                                                                                   |
|  [Cryptographic Verification Engine]                                              |
|  - 128-bit HMAC-SHA256 Challenge Verification with Grace Clock Drift Window       |
|  - ECDSA / RSA Signature Verification (Android Keystore / iOS Keychain)          |
|  - Per-Student Replay Protection & RSSI Distance Verification                     |
+--------------------------+---------------------------------+----------------------+
                           |                                 |
               Authoritative ACID Reads/Writes     Asynchronous Live Projections
                           |                       (Admin SDK, Read-Only to Clients)
                           v                                 v
+------------------------------------+  +-------------------------------------------+
|      POSTGRESQL 16 (AUTHORITY)     |  |         CLOUD FIRESTORE (READ-ONLY)       |
|                                    |  |                                           |
|  - sessions (UUID, secret_hash)    |  |  - sessions/{id} (status, times)          |
|  - users (roles, roll numbers)     |  |  - sessions/{id}/live/current (challenges)|
|  - enrollments (active status)     |  |  - sessions/{id}/attendance/{uid}         |
|  - attendance_records (UNIQUE UQ)  |  |    (Client writes strictly denied)        |
|  - devices (keys & attestation)    |  +-------------------------------------------+
|  - consumed_nonces (anti-replay)   |
|  - device_attestation_challenges  |
|  - overrides & audit_log (audit)   |
+------------------------------------+
```

### Entry Points
- **Client Application**: [`lib/main.dart`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/lib/main.dart) -> `ProviderScope` -> `AppRouter` -> Role-gated views (`/student`, `/faculty`, `/admin`).
- **Backend Application**: [`backend/app/main.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/main.py) -> FastAPI Application with lifecycle database pool, CORS, and Security Middlewares.
- **REST Routers**:
  - `/api/v1/sessions`: [`backend/app/routers/sessions.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/routers/sessions.py) (Session lifecycle, roster retrieval, manual override).
  - `/api/v1/attendance`: [`backend/app/routers/checkin.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/routers/checkin.py) (Cryptographic proximity check-in, student history).
  - `/api/v1/devices`: [`backend/app/routers/devices.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/routers/devices.py) (Keystore public key registration and revocation).
  - `/api/v1/auth`: [`backend/app/routers/auth.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/routers/auth.py) (Zero-trust profile sync and role assignment).

---

## 2. Authoritative Data Flow & Security Boundaries

1. **Session Inception**:
   - Faculty starts session via `POST /api/v1/sessions/start`.
   - FastAPI generates 256-bit entropy `ephemeral_token`, stores `secret_hash` in PostgreSQL `sessions` table, and returns `ephemeral_token` strictly to the starting faculty client.
   - Flutter initializes `CodeRotator` using the server-returned `backendSessionId` and `sessionSecret`.

2. **Proximity Challenge Broadcast & Scanning**:
   - Faculty broadcasts 128-bit rotating HMAC-SHA256 challenge via BLE manufacturer data under service UUID `00000001-a1b2-c3d4-e5f6-7a8b9c0d1e2f`.
   - Challenge rotates every 20 seconds, synchronized to server Unix epoch step boundaries (`floor(epoch / 20)`).
   - Student scans BLE advertisements, filtering out standard Bluetooth SIG devices, and extracts the active 32-hex classroom challenge.

3. **Cryptographic Check-In Submission**:
   - Student signs `${sessionId}:${nonce}:${timestamp}` using hardware-backed private key (Android Keystore / iOS Keychain).
   - Client sends check-in payload to FastAPI: `POST /api/v1/attendance/check-in`.
   - FastAPI verifies:
     - Student JWT authentication and active course enrollment.
     - Proximity challenge validity across current, previous, and next rotation windows ($W \in [T-1, T+1]$).
     - Hardware signature validity against registered public key.
     - Observed RSSI meets or exceeds session threshold.
     - Single-attendance replay constraint (`uq_session_student`).
   - Transaction commits to PostgreSQL 16.
   - Verified record is projected into Cloud Firestore for real-time faculty UI updates via Firebase Admin SDK. Direct client writes to Firestore attendance are disabled (`allow write: if false;`).

---

## 3. Dependency Map

### Backend Core
- Python 3.13, FastAPI 0.115, SQLAlchemy 2.0 (Asyncpg), Alembic, Pydantic v2.
- Cryptography (ECDSA, RSA, SHA256), DuckDB, PyArrow, Pillow, QRCode.
- PostgreSQL 16 ACID database server.

### Frontend Core
- Flutter 3.29.0 / Dart 3.7.0.
- `flutter_riverpod` (v2), `go_router` (v14), `firebase_core`, `firebase_auth`, `cloud_firestore`.
- `flutter_blue_plus` (v1.35.3), `flutter_secure_storage` (v9), `local_auth` (v2), `crypto`.

---

## 4. Hardened Security & Anti-Fraud Mechanisms (Phase 4 Updates)

### 4.1 Server-Side RSSI Verification
- **Validation**: All check-in payloads must include `observed_rssi`. FastAPI strictly rejects values outside `[-120, 0]` dBm with `400 Bad Request`.
- **Threshold Check**: If `observed_rssi < session.rssi_threshold`, check-in is rejected (`400 Proximity threshold unmet`).
- **Physical Boundary Acknowledgment**: RSSI alone cannot mathematically guarantee absolute physical presence on compromised/rooted devices without time-of-flight (UWB) or cryptographically signed sensor enclaves. It serves as an active barrier against naive and unmodified remote check-in attempts.

### 4.2 Nonce and Signature Replay Protection
- **Tracking Table**: `consumed_nonces` table with unique constraints `uq_session_signature_hash` and `uq_session_student_nonce`.
- **Clock Skew Enforcement**: Student check-in timestamps (`client_timestamp`) must not exceed 10 seconds in the future or 60 seconds in the past relative to authoritative server time.
- **Atomic Invalidation**: On valid check-in, signature hash and client nonce are committed atomically with the `AttendanceRecord`. Re-submitting the same payload or signature yields `409 Attendance signature or nonce has already been consumed`.

### 4.3 Hardware Device Attestation Pipeline
- **Attestation Flow**: Clients request a 256-bit cryptographically random challenge via `POST /api/v1/devices/attestation-challenge` (300-second TTL).
- **Two-Tier Key Trust**:
  - `key_registered`: Unattested public keys generated on device. Can be used for basic pilot testing.
  - `hardware_attested`: Keys with verified X.509 certificate chains containing Android Keymaster/KeyMint extension OID `1.3.6.1.4.1.11129.2.1.17` rooted in Google Hardware Root CA, or Apple DeviceCheck/App Attest CBOR attestations.
- **Revocation**: Device public keys can be revoked via `POST /api/v1/devices/{id}/revoke`.

### 4.4 Authoritative Manual Override & Concurrency Protection
- **Audit Logging**: Manual overrides persist `override_reason` and `marked_by` directly onto `attendance_records`, insert a row into `overrides`, and append an immutable event to `audit_log`.
- **Concurrency Isolation**: Database operations use nested transaction savepoints (`async with db.begin_nested():`) to catch duplicate check-in collisions (`IntegrityError`) and idempotently update status to `present_override` without throwing 500 errors.

### 4.5 Runtime Network Configuration for Physical Devices
- **Flutter Client**: Dynamic API host configuration via `AttendanceApiService.setRuntimeOverrideUrl` and `Icons.dns_outlined` dialog on `LoginScreen`.
- **Certificate Handling**: Debug builds allow self-signed certificates and direct local IP testing, avoiding Android emulator `10.0.2.2` routing traps on physical hardware.

