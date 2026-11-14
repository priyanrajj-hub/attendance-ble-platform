# Enterprise Production Deployment & Operations Guide
**Amrita BLE Proximity Attendance Platform**  
**Document Classification:** Production Operations Manual  
**Revision:** 2.0 (PostgreSQL Authority Architecture)  

---

## 1. System Architecture Overview

```
                     ┌─────────────────────────────────────────┐
                     │          Flutter Mobile Client          │
                     │  (Android Keystore / iOS Keychain)      │
                     └───────────────┬─────────────────────────┘
                                     │
           1. Authenticate           │ 2. Submit Proximity Check-In
           (ID Token)                │    (Signed Challenge + RSSI)
                                     ▼
┌───────────────────────┐      ┌─────────────────────────────────────────┐
│   Firebase Auth       │      │         FastAPI Backend Engine          │
│   (Identity & Claims) │◄─────┤  - RBAC & Domain Authorization          │
└───────────────────────┘      │  - Asymmetric Signature Verification    │
                               │  - TOTP Rotating Challenge Service      │
                               │  - Replay & Concurrency Engine          │
                               └───────────────┬─────────────────────────┘
                                               │
                                               │ 3. Atomic Transaction
                                               ▼
                               ┌─────────────────────────────────────────┐
                               │           PostgreSQL Database           │
                               │  - sessions & attendance_records        │
                               │  - users & devices (Public Keys)        │
                               │  - courses & enrollments                │
                               └─────────────────────────────────────────┘
```

---

## 2. Environment Configuration

### Directory Hygiene
- Repository root contains the public `.env.example` template.
- All live credentials, service accounts, and database passwords must reside strictly in local `.env` files, which are 100% ignored by the root `.gitignore`.

### Required Environment Variables

```bash
# FastAPI Application
PROJECT_NAME="Amrita BLE Attendance Platform API"
VERSION="1.0.0"
ENVIRONMENT="production"
API_V1_STR="/api/v1"

# Database Connection (PostgreSQL 15+)
DATABASE_URL="postgresql+asyncpg://app_user:StrongSecretPassword@postgres-db.internal:5432/attendance_db"
SYNC_DATABASE_URL="postgresql://app_user:StrongSecretPassword@postgres-db.internal:5432/attendance_db"

# Firebase Admin SDK
FIREBASE_PROJECT_ID="attendance-ble-production"
FIREBASE_SERVICE_ACCOUNT_PATH="/etc/secrets/firebase-service-account.json"

# CORS & Security
CORS_ORIGINS=["https://attendance.amrita.edu"]
MAX_CSV_UPLOAD_SIZE_BYTES=2097152
```

---

## 3. Database Migration & Provisioning

Execute migrations using Alembic:

```bash
cd backend
# Verify database connectivity
python -c "import psycopg2; print('Database reachable')"

# Run transactional database schema upgrades to latest revision
alembic upgrade head
```

### Rollback Strategy
If a migration must be reverted:
```bash
# Rollback single revision
alembic downgrade -1

# Rollback to initial baseline
alembic downgrade 001_initial_schema
```

---

## 4. Backend Service Deployment (Systemd / Docker)

### Systemd Service Configuration (`/etc/systemd/system/amrita-attendance.service`)

```ini
[Unit]
Description=Amrita Attendance FastAPI Backend Service
After=network.target postgresql.service

[Service]
User=appuser
Group=appuser
WorkingDirectory=/opt/attendance-ble-platform/backend
EnvironmentFile=/opt/attendance-ble-platform/backend/.env
ExecStart=/opt/attendance-ble-platform/backend/.venv/bin/gunicorn app.main:app \
    --workers 4 \
    --worker-class uvicorn.workers.UvicornWorker \
    --bind 0.0.0.0:8000 \
    --access-logfile /var/log/amrita/access.log \
    --error-logfile /var/log/amrita/error.log \
    --timeout 30

Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

Enable and start the daemon:
```bash
sudo systemctl daemon-reload
sudo systemctl enable amrita-attendance
sudo systemctl start amrita-attendance
sudo systemctl status amrita-attendance
```

---

## 5. Mobile Application Release Build (Flutter)

### Android Production Keystore Setup
Ensure `android/key.properties` is configured:
```properties
storePassword=YourKeystorePassword
keyPassword=YourKeyPassword
keyAlias=amrita-attendance-release
storeFile=/path/to/release.keystore
```

### Compiling Release APK & App Bundle
```bash
flutter clean
flutter pub get

# Universal Release APK
flutter build apk --release

# Split Per-ABI Release APKs (Recommended for distribution)
flutter build apk --split-per-abi --release

# Production Google Play App Bundle (AAB)
flutter build appbundle --release
```

---

## 6. Operational Monitoring & Routine Maintenance

### 1. Backend Health Probes
- Liveness Probe: `GET /api/v1/health/live`
- Database Readiness Probe: `GET /api/v1/health/ready`

### 2. Attendance Ledger Reconciliation
To verify synchronization between ephemeral mobile Firestore documents and the authoritative PostgreSQL database:
```bash
cd backend
# Dry-run audit report
python scripts/reconcile_attendance.py

# Reconcile specific session ID
python scripts/reconcile_attendance.py --session-id "5128f554-d68f-4f78-b67d-dea432aa1f04"
```

### 3. Key Rotation & Revocation
To revoke a student device in case of loss or hardware replacement:
```bash
curl -X POST "https://attendance.amrita.edu/api/v1/devices/revoke" \
  -H "Authorization: Bearer <ADMIN_OR_STUDENT_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"device_id": "<UUID>", "reason": "Student phone replaced"}'
```
