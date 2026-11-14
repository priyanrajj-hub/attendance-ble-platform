# Authoritative Cryptographic Challenge Protocol Specification
**Amrita BLE Proximity Attendance Platform**  
**Document Revision:** 3.0 (Synchronized 128-Bit HMAC-SHA256 Challenge Architecture)  
**Standard Status:** Production Cryptographic Standard  

---

## 1. Protocol Architecture & Lifecycle

The attendance challenge protocol establishes cryptographic proximity binding between the broadcasting instructor device and student scanning devices, independently verifiable by the authoritative FastAPI + PostgreSQL backend.

```
[1. Faculty App: POST /api/v1/sessions/start]
                     │
                     ▼ Returns 256-bit CSPRNG Secret (ephemeral_token)
[2. Faculty Broadcaster: Derives 128-bit Challenge on 20s Steps]
                     │
                     ▼ Broadcasts 128-bit UUID via BLE Peripheral
[3. Student Scanner: Extracts 128-bit Challenge from UUID]
                     │
                     ▼ Signs (SessionID : Challenge : ClientTimestamp) with Keystore Key
[4. Student App: POST /api/v1/attendance/check-in]
                     │
                     ▼
[5. FastAPI Backend: Independently Derives Valid Steps (t0, t-1, t-2, t+1)]
                     │
                     ▼ If Match & Sig Valid: Transactionally Writes to PostgreSQL
[6. Authoritative Confirmation: Student Receives HTTP 200 Present Receipt]
```

---

## 2. Mathematical Definition

### 2.1 Master Session Secret Generation
Upon session initiation by an authorized faculty member, the backend generates 256 bits of entropy using a cryptographically secure pseudorandom number generator:
$$K_{\text{session}} \in \{0, 1\}^{256} \quad (\text{64-character hexadecimal string})$$
- Stored exclusively in PostgreSQL `sessions.secret_hash`.
- Disclosed strictly to the initiating faculty device over TLS (`ephemeral_token`).
- **Zero-knowledge guarantee:** Never stored in Cloud Firestore; never exposed to student accounts.

### 2.2 Time-Step Synchronization
Both the mobile broadcaster and backend verifier evaluate discrete time steps based on UTC epoch seconds:
$$\text{step} = \left\lfloor \frac{t_{\text{epoch\_seconds}}}{T_{\text{rotation}}} \right\rfloor \quad \text{where } T_{\text{rotation}} = 20\text{ seconds}$$

### 2.3 Challenge Value Derivation
Every challenge is cryptographically bound to the unique session identifier and current time step:
$$M = \text{session\_id} \parallel ":" \parallel \text{str}(\text{step})$$
$$\text{Digest}_{256} = \text{HMAC-SHA256}(K_{\text{session}}, M)$$
$$\text{Challenge}_{128} = \text{Digest}_{256}[0 \dots 15] \quad (\text{128 bits} = \text{32 hex characters})$$

### 2.4 BLE Advertisement Payload Framing
To comply with physical Bluetooth Low Energy advertising constraints across both Android (BluetoothLeAdvertiser) and iOS (CBPeripheralManager):
- The 32-hex-character challenge is formatted as a standard RFC4122 128-bit Service Class UUID (8-4-4-4-12):
$$\text{UUID}_{128} = C[0\dots 7] \parallel "-" \parallel C[8\dots 11] \parallel "-" \parallel C[12\dots 15] \parallel "-" \parallel C[16\dots 19] \parallel "-" \parallel C[20\dots 31]$$
- Total advertising frame length: 16-byte UUID + 2-byte header = 18 bytes (well within the 31-byte legacy BLE PDU limit).

### 2.5 Backend Verification & Expiration Gates
When an attendance payload is received at time $t_{\text{recv}}$, the backend computes the reference step $s_0 = \lfloor t_{\text{recv}} / 20 \rfloor$ and accepts challenges matching:
$$s \in \{s_0 - 2, \, s_0 - 1, \, s_0, \, s_0 + 1\}$$
- **Total Expiration Lifespan:** Maximum 60 seconds (accounting for 20s broadcast interval, 10s scan window, and network transit).
- **Clock Skew Tolerance:** $\pm 20$ seconds ($s_0 + 1$) for device clock drift.
- Challenges outside this window are rejected with **HTTP 403 Forbidden**.

---

## 3. Standard Cryptographic Test Vectors

These test vectors must produce bit-for-bit identical results in Dart (`ChallengeCrypto`) and Python (`ChallengeService`).

### Test Vector 1
- **Session Secret:** `0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef`
- **Session ID:** `550e8400-e29b-41d4-a716-446655440000`
- **Time Step:** `58000000`
- **Input String:** `550e8400-e29b-41d4-a716-446655440000:58000000`
- **128-Bit Challenge (Hex):** `3a7bb516e37fe7d07c3d9d400e404434`
- **Advertised BLE UUID:** `3a7bb516-e37f-e7d0-7c3d-9d400e404434`

### Test Vector 2
- **Session Secret:** `a7f92b4c81d3e5f60123456789abcdefa7f92b4c81d3e5f60123456789abcdef`
- **Session ID:** `e2e00000-0000-0000-0000-000000000001`
- **Time Step:** `100000000`
- **Input String:** `e2e00000-0000-0000-0000-000000000001:100000000`
- **128-Bit Challenge (Hex):** `a5ff3c823f09f3eee7d34ea41b13c80c`
- **Advertised BLE UUID:** `a5ff3c82-3f09-f3ee-e7d3-4ea41b13c80c`

### Test Vector 3
- **Session Secret:** `deadbeefcafebabe0123456789abcdefdeadbeefcafebabe0123456789abcdef`
- **Session ID:** `77777777-8888-9999-aaaa-bbbbccccdddd`
- **Time Step:** `999999999`
- **Input String:** `77777777-8888-9999-aaaa-bbbbccccdddd:999999999`
- **128-Bit Challenge (Hex):** `323214f238d073724db658924c7142e2`
- **Advertised BLE UUID:** `323214f2-38d0-7372-4db6-58924c7142e2`

---

## 4. Test Verification Summary

- **Flutter Implementation:** [`lib/ble/challenge_crypto.dart`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/lib/ble/challenge_crypto.dart)
  - Unit Test: [`test/unit/crypto_cross_test.dart`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/test/unit/crypto_cross_test.dart) — **PASSED**
- **Python Backend Implementation:** [`backend/app/services/challenge_service.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/app/services/challenge_service.py)
  - Unit Test: [`backend/tests/test_challenge_crypto_vectors.py`](file:///C:/Users/PRIYANRAJ%20J/.gemini/antigravity/scratch/attendance-ble-platform/backend/tests/test_challenge_crypto_vectors.py) — **PASSED**
- **Result:** 100% bit-for-bit parity across all vectors and edge cases.
