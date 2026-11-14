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

---

## 3. Secret Management, Git Hygiene & Credential Governance

### 3.1 Overview
The Amrita BLE Attendance Platform implements a zero-leakage security posture designed to prevent accidental leakage of database credentials, encryption master keys, Firebase service account keys, mobile signing keystores, and personal institutional data into Git version control.

### 3.2 Master GitIgnore Architecture
The root `.gitignore` enforces strict exclusions across 12 distinct asset categories:
1. **Environment Files**: Blocks `.env`, `.env.*`, `*.env`, `backend/env/.env*`, while preserving template files `!.env.example` and `!**/.env.example`.
2. **Python & FastAPI**: Excludes `__pycache__/`, `*.pyc`, distribution artifacts (`dist/`, `build/`), virtual environments (`.venv/`, `venv/`, `env/`), test/coverage caches (`.pytest_cache/`, `htmlcov/`, `.coverage`).
3. **Flutter & Dart**: Excludes `.dart_tool/`, `.packages`, `.pub/`, `.pub-cache/`, `build/`, while strictly preserving `pubspec.lock` for reproducible dependency trees.
4. **Android Security**: Excludes `android/local.properties`, `android/key.properties`, `android/.gradle/`, `.cxx/`, build outputs, debug/release APKs (`*.apk`, `*.aab`), keystores (`*.jks`, `*.keystore`), and `android/app/google-services.json` (preserving only `google-services.json.example`).
5. **iOS Security**: Excludes `ios/Pods/`, `ios/.symlinks/`, ephemeral Flutter configs, `GoogleService-Info.plist`, provisioning profiles (`*.mobileprovision`), and signing certificates (`*.p12`, `*.cer`, `*.p8`).
6. **Firebase & Cloud Credentials**: Excludes `service-account*.json`, `*firebase-admin*.json`, GCP client secrets, and Firebase emulator debug logs.
7. **Private Keys & TLS Certificates**: Excludes `*.pem`, `*.key`, `*.ppk`, `*.der`, `*.crt`, `id_rsa`, `id_ed25519`.
8. **Secrets & Vault Files**: Excludes `secrets/`, `credentials/`, `*.secret`, `vault.json`, `token.json`, and API token dumps.
9. **Databases & Backups**: Excludes `*.db`, `*.sqlite`, `*.sqlite3`, `*.dump`, `*.sql.gz`, `*.bak`, while strictly preserving Alembic database migration scripts in `backend/alembic/versions/*.py`.
10. **Data Lakehouse & Telemetry**: Excludes `*.parquet`, `*.arrow`, `*.feather`, `*.duckdb`, `*.wal`, and the `backend/data/` analytics partitions.
11. **System & Temporary Files**: Excludes `*.log`, `npm-debug.log*`, `*.tmp`, `*.swp`, OS metadata (`.DS_Store`, `Thumbs.db`).
12. **IDE & Local Tooling**: Excludes `.idea/`, `.vscode/`, `*.iml`, `.gemini/`, `.agents/`, `.claude/`.

Complementing `.gitignore`, root `.dockerignore` and `backend/.dockerignore` prevent build contexts from packaging secrets, virtual environments, or development artifacts into container layers.

### 3.3 Environment Configuration & Local Setup
Developers must configure local environments using template files:
```bash
# 1. Clone repository
git clone https://github.com/priyanrajj-hub/attendance-ble-platform.git
cd attendance-ble-platform

# 2. Instantiate root and backend environment configurations
cp .env.example .env
cp backend/.env.example backend/.env

# 3. Generate high-entropy secret keys for AES-256-GCM envelope encryption
python -c "import secrets; print(secrets.token_hex(32))"
```

#### Required Environment Variables
| Variable | Scope | Description | Production Source |
|---|---|---|---|
| `DATABASE_URL` | Backend | Async PostgreSQL connection string (`postgresql+asyncpg://...`) | Cloud SQL / Secret Manager |
| `SYNC_DATABASE_URL` | Backend | Sync PostgreSQL connection string for Alembic migrations | Cloud SQL / Secret Manager |
| `SECRET_KEY` | Backend | Master key for AES-256-GCM session secrets & HMAC validation | KMS / Secret Manager |
| `FIREBASE_PROJECT_ID` | Multi-tier | Google Cloud / Firebase project identifier | App Configuration / CI Secret |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Backend | Absolute path to backend GCP service account JSON key | Mounted secret volume / KMS |
| `BLE_NAMESPACE_HEX` | Mobile/Backend | Hex-encoded 10-byte BLE Eddystone namespace filter | App Configuration |
| `BLE_ROTATION_INTERVAL_SECONDS` | Mobile/Backend | Synchronized epoch rotation step size (default: 20s) | App Configuration |
| `BLE_RSSI_CHECKIN_THRESHOLD_DBM` | Mobile/Backend | Maximum allowable signal attenuation (default: -80 dBm) | App Configuration |
| `HUGGINGFACE_API_TOKEN` | Backend | Optional API token for institutional AI agent analytics | Secret Manager |

### 3.4 Production Secret Management & CI/CD Governance
- **Zero Hardcoded Secrets**: In production, environment variables must never be baked into container images or checked into source code. Inject them at container runtime via Kubernetes Secrets, Google Cloud Run Secret Mounts, or AWS Secrets Manager.
- **GitHub Actions Least Privilege**:
  - The CI workflow declares top-level `permissions: contents: read` to prevent malicious PRs from modifying repository contents or creating releases.
  - Production deployments use scoped GitHub Environment Secrets with mandatory reviewer approval.
- **Automated Secret Scanning (Gitleaks)**:
  - Gitleaks v8 is integrated into `.github/workflows/ci.yml` with `fetch-depth: 0` to scan entire Git commit trees on every push and pull request.
  - Repository-level `.gitleaks.toml` defines cryptographic test vector allowlists and public client SDK exceptions with surgical precision.

### 3.5 Security Disclosure & Remediation: Historical Commit `bfb74bd88fa6df006fb40216a2b140faa83cde27`
- **Audit Finding**: In early commit `bfb74bd88fa6df006fb40216a2b140faa83cde27` (dated 2026-07-25), an unencrypted `android/app/google-services.json` was tracked in git before being removed from the working tree in commit `4c0415f`.
- **Compensating Security Controls**:
  1. Client-side Firestore rules now enforce `allow write: if false;`, eliminating the ability for an attacker with the Firebase API key to forge attendance records directly.
  2. The Google Cloud API key (`AIza...`) embedded in client configs is public-facing by design in Firebase Android architectures and is intended only for client identification.
- **Required Production Remediation Checklist**:
  - [x] Working tree sanitized: live `google-services.json` untracked and ignored; replaced by `google-services.json.example`.
  - [x] Gitleaks configured with targeted allowlist for commit `bfb74bd88fa6df006fb40216a2b140faa83cde27`.
  - [ ] **Administrator Action**: Access [Google Cloud Console Credentials](https://console.cloud.google.com/apis/credentials), locate the Android API key, and enforce an application restriction to the package name `com.amrita.attendance` and the SHA-1 fingerprint of the production release keystore.
  - [ ] **Optional Historical Purge**: If total removal from Git object storage is desired, repository administrators can execute `git filter-repo --invert-paths --path android/app/google-services.json --force` and coordinate a force-push across all contributor clones.
