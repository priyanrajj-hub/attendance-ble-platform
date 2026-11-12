# Architecture Decision Records (ADRs)

## ADR-0001: Phase 0 Repository Hygiene, Secret Management, and Git Strategy

### Context
The repository contained tracked binaries (`attendance_ble_final.apk` 52 MB), debug logs, backup files, and committed Android configuration files (`google-services.json`). Furthermore, commit `56c00ad` introduced ~100 MB of node executables and build archives into git history.

### Decision
1. **Untrack Artifacts**: Remove `attendance_ble_final.apk`, `debug.log`, `firebase.json.bak`, `.flutter-plugins-dependencies`, and `android/app/google-services.json` from git tracking.
2. **Configuration Templating**: Commit `android/app/google-services.json.example` and `.env.example`.
3. **CI Secret Decoupling**: Inject `google-services.json` in GitHub Actions via base64 encoded repository secret `GOOGLE_SERVICES_JSON_BASE64`.
4. **Git History Rewrite Strategy**: Defer history rewriting (`git-filter-repo`) to a distinct milestone. Complete cleanup commits first, mandate a full mirror backup, and require explicit approval prior to running `git-filter-repo`.
5. **Secret Scanning**: Adopt Gitleaks in CI (`.github/workflows/security-scan.yml`) rather than ad-hoc scanning scripts.
6. **API Key Security**: Treat client-side Firebase API keys as identifiable assets requiring Google Cloud Console application restrictions (package name + SHA-1 fingerprint) and API restrictions, backed by Firebase App Check.

### Status
Accepted

---

## ADR-0002: System of Record & Live Session Dual-Store Architecture

### Context
Attendance systems require relational integrity, append-only auditing, institutional roster management, and complex SQL reporting. Concurrently, mobile BLE proximity sessions require low-latency live state synchronization and roster streaming to faculty screens.

### Decision
1. **System of Record**: PostgreSQL (hosted on AWS RDS `ap-south-1`) is the authoritative source of truth for user accounts, courses, enrollments, devices, and finalized attendance records.
2. **Ephemeral Live State**: Cloud Firestore is retained exclusively as an ephemeral realtime synchronization layer for active sessions.
3. **Server Authority**: The mobile client is untrusted. Final attendance verification, device signature validation, and recording are executed server-side via a typed FastAPI backend.
4. **Reconciliation**: A background task periodically reconciles active Firestore session records with PostgreSQL.

### Status
Proposed (Phase 3 Target)

---

## ADR-0003: Claude Model Configuration

### Context
Anthropic model identifiers update periodically. Hardcoding model snapshot strings in application code leads to deprecation issues and lack of environment flexibility.

### Decision
Model identifiers for the AI policy and query assistant are made configurable via the environment variable `ANTHROPIC_MODEL`, defaulting to a configurable production snapshot (e.g. `claude-3-5-sonnet-20241022` or `claude-3-5-haiku-20241022`). Applications query models dynamically or accept administrator configuration from environment variables.

### Status
Accepted
