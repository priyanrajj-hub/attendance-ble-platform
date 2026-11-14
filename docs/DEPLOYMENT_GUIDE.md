# PRODUCTION DEPLOYMENT & INFRASTRUCTURE GUIDE
**Amrita BLE Proximity Attendance Platform**  

---

## 1. Prerequisites

- **PostgreSQL 16** with SSL enabled and connection pool limits configured ($\ge 50$ connections).
- **Python 3.13** runtime environment or Docker container engine.
- **Firebase Project** with Authentication, Cloud Firestore, and Service Account credentials.
- **Reverse Proxy**: NGINX / Cloudflare with TLS 1.3, HSTS, and rate limiting.

---

## 2. Environment Configuration

Create production `.env` (never commit to version control):

```bash
# Database Authority
DATABASE_URL=postgresql+asyncpg://app_user:StrongPassword@postgres-db.internal:5432/amrita_attendance

# Authentication & Firebase
FIREBASE_PROJECT_ID=amrita-attendance-prod
GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/firebase-admin-key.json

# Security & CORS
ALLOWED_ORIGINS=https://attendance.amrita.edu
SECRET_KEY=generate_with_openssl_rand_hex_32
ENVIRONMENT=production
```

---

## 3. Database Migration Execution

Before running the API service, execute all Alembic migrations to apply constraints, indices, and tables:

```bash
cd backend
alembic upgrade head
```

---

## 4. Running Backend Service with Gunicorn / Uvicorn

```bash
gunicorn app.main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --access-logfile - \
  --error-logfile -
```

---

## 5. Flutter Production Build

```bash
# Android App Bundle (AAB) for Google Play
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.attendance.amrita.edu

# iOS IPA for TestFlight / App Store
flutter build ipa --release --dart-define=API_BASE_URL=https://api.attendance.amrita.edu
```
