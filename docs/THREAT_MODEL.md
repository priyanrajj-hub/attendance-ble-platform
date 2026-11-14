# THREAT MODEL & MITIGATION ARCHITECTURE
**Amrita BLE Proximity Attendance Platform**  
*Methodology:* STRIDE Threat Modeling for Proximity Attendance  

---

## 1. Threat Analysis

### 1. Spoofing Identity (S)
- **Threat**: An absent student gives their credentials to a friend in class.
- **Mitigation**:
  - Hardware device binding (`devices` table). Each user is bound to one active hardware key.
  - Biometric authentication (`local_auth`) challenged upon app launch and check-in attempt.
  - Institutional domain validation enforced during registration and profile sync (`@cb.students.amrita.edu`).

### 2. Tampering with Data (T)
- **Threat**: Student intercepts check-in network traffic and modifies session ID, timestamp, or RSSI value.
- **Mitigation**:
  - The check-in request requires a digital signature over `session_id:nonce:timestamp` generated inside the hardware Keystore.
  - Backend verifies signature with the enrolled public key before processing.
  - TLS 1.3 encryption prevents man-in-the-middle modification.

### 3. Repudiation (R)
- **Threat**: Student claims attendance was recorded without their presence, or faculty falsely denies attendance.
- **Mitigation**:
  - Digital signature provides non-repudiation.
  - Every attendance record in PostgreSQL stores `verified_at`, `method`, `signature_verified`, `device_id`, and `rssi_observed`.
  - Manual overrides record `marked_by` faculty ID and mandatory rationale string ($\ge 3$ characters).

### 4. Information Disclosure (I)
- **Threat**: A student eavesdrops on BLE signals or interrogates Firestore / API endpoints to obtain classroom session secrets.
- **Mitigation**:
  - `secret_hash` is never exposed over student-accessible APIs or Firestore collections.
  - Only the 32-hex HMAC challenge is broadcast over BLE; reversing HMAC-SHA256 to uncover the 256-bit session secret is computationally infeasible.

### 5. Denial of Service (DoS)
- **Threat**: Attacker floods check-in endpoint with fake BLE nonces.
- **Mitigation**:
  - Strict rate limiting and authentication checks prior to cryptographic verification.
  - Single check-in constraint (`uq_session_student`) prevents database bloat from duplicate calls.

### 6. Elevation of Privilege (E)
- **Threat**: Student manipulates JWT claims or calls administrative / faculty endpoints.
- **Mitigation**:
  - FastAPI RBAC dependency injection verifies role from PostgreSQL user record, not unverified client-provided tokens.
  - Firestore security rules deny direct client collection writes.
