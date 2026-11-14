# POSTGRESQL 16 DATABASE SCHEMA
**Amrita BLE Proximity Attendance Platform**  

---

## 1. Relational Entity ERD

```mermaid
erDiagram
    USERS ||--o{ ENROLLMENTS : registers
    USERS ||--o{ SESSIONS : instructs
    USERS ||--o{ DEVICES : owns
    COURSES ||--o{ ENROLLMENTS : contains
    COURSES ||--o{ SESSIONS : hosts
    SESSIONS ||--o{ ATTENDANCE_RECORDS : logs
    USERS ||--o{ ATTENDANCE_RECORDS : attends

    USERS {
        uuid id PK
        string firebase_uid UK
        string email UK
        string role
        string status
        string roll_number UK
    }

    SESSIONS {
        uuid id PK
        uuid course_id FK
        uuid started_by FK
        string room_label
        int rssi_threshold
        string secret_hash
        timestamp opens_at
        timestamp closes_at
        string status
    }

    ATTENDANCE_RECORDS {
        uuid id PK
        uuid session_id FK
        uuid student_id FK
        uuid device_id FK
        string method
        int rssi_observed
        bool signature_verified
        timestamp verified_at
        string status
    }

    DEVICES {
        uuid id PK
        uuid user_id FK
        string public_key_fingerprint UK
        text public_key_pem
        string platform
        string attestation_status
        timestamp registered_at
        timestamp revoked_at
    }
```

---

## 2. Table Constraints & Indices

1. `attendance_records`:
   - Unique Constraint: `UniqueConstraint("session_id", "student_id", name="uq_session_student")`
   - Check Constraint: `CheckConstraint("method IN ('ble_signed_nonce', 'faculty_manual_override')", name="check_attendance_method")`
   - Check Constraint: `CheckConstraint("status IN ('present', 'disputed', 'revoked')", name="check_attendance_status")`
   - Index: `Index("idx_attendance_student", "student_id", "verified_at")`

2. `devices`:
   - Partial Index: `Index("idx_devices_user", "user_id", postgresql_where=("revoked_at IS NULL"))`
   - Check Constraint: `CheckConstraint("platform IN ('android', 'ios')", name="check_device_platform")`
