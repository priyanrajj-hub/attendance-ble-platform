# FASTAPI BACKEND API REFERENCE
**Amrita BLE Proximity Attendance Platform**  
*Base Path:* `/api/v1`  

---

## 1. Attendance Check-In

### `POST /api/v1/attendance/check-in`
Verifies proximity and records attendance for the authenticated student.

- **Headers**: `Authorization: Bearer <Firebase_ID_Token>`
- **Request Body**:
  ```json
  {
    "session_id": "00000000-0000-0000-0000-000000000001",
    "ephemeral_nonce": "4f5a8b2c1d3e9f0a5b6c7d8e9f0a1b2c",
    "observed_rssi": -65,
    "signature": "3045022100...",
    "public_key_fingerprint": "a1b2c3d4...",
    "client_timestamp": 1731600000000
  }
  ```
- **Response**: `200 OK`
  ```json
  {
    "attendance_id": "11111111-1111-1111-1111-111111111111",
    "session_id": "00000000-0000-0000-0000-000000000001",
    "student_id": "22222222-2222-2222-2222-222222222222",
    "status": "present",
    "method": "ble_signed_nonce",
    "verified_at": "2026-11-14T14:00:00Z",
    "already_marked": false,
    "signature_verified": true,
    "message": "Attendance verified and recorded successfully."
  }
  ```

---

## 2. Session Management

### `POST /api/v1/sessions/start`
Starts a new BLE attendance session. Only accessible to course-assigned faculty or admins.
- **Request Body**:
  ```json
  {
    "course_id": "CSE450",
    "room_label": "AB3-401",
    "duration_minutes": 50,
    "rssi_threshold": -75
  }
  ```
- **Response**: `201 Created` (Discloses `ephemeral_token` strictly to the starting faculty).

### `POST /api/v1/sessions/{session_id}/stop`
Closes an active attendance session.

### `GET /api/v1/sessions/{session_id}/roster`
Returns live enrollment and attendance status for all students in the course. Restricted to the assigned course instructor or administrator.

---

## 3. Attendance Disputes & Correction Requests

### `POST /api/v1/disputes`
Submits an attendance grievance/dispute for a missed session.
- **Role**: `student` (Must be enrolled in the session's course).
- **Request Body**:
  ```json
  {
    "session_id": "00000000-0000-0000-0000-000000000001",
    "reason": "Phone Bluetooth radio failed to advertise during class. Seated in Row 3."
  }
  ```
- **Response**: `201 Created`

### `GET /api/v1/disputes`
Lists disputes scoped to the requesting role:
- `student`: sees own submitted disputes.
- `faculty`: sees disputes for sessions belonging to courses taught by instructor.
- `admin`: sees all disputes.

### `POST /api/v1/disputes/{dispute_id}/resolve`
Approves or rejects a student's attendance dispute.
- **Role**: `faculty` (Assigned instructor) or `admin`.
- **Request Body**:
  ```json
  {
    "decision": "approved",
    "resolution_notes": "Verified student was present in seat B-12."
  }
  ```
- **Response**: `200 OK` (Updates attendance record to `present`, inserts `Override` row, and commits immutable `AuditLog`).

---

## 4. Hardware Device Binding & Attestation

### `POST /api/v1/devices/attestation-challenge`
Issues a 256-bit cryptographically secure random challenge with 300-second TTL for remote hardware attestation.

### `POST /api/v1/devices/register`
Registers device public key PEM. If an X.509 Keymaster/KeyMint certificate chain or Play Integrity token is supplied, sets status to `hardware_attested`; otherwise defaults to `key_registered`.


### `POST /api/v1/sessions/{session_id}/manual-override`
Authoritative manual attendance override recorded by the session faculty.
- **Request Body**:
  ```json
  {
    "student_id": "CB.EN.U4CSE22001",
    "reason": "Verified in person; student device battery exhausted."
  }
  ```

---

## 3. Device Binding

### `POST /api/v1/devices/register`
Registers or updates the user's hardware-backed public key.
- **Request Body**:
  ```json
  {
    "public_key_pem": "-----BEGIN PUBLIC KEY-----\n...",
    "platform": "android",
    "device_model": "Pixel 8",
    "os_version": "Android 14"
  }
  ```

### `GET /api/v1/devices/me`
Retrieves currently registered hardware key information.
