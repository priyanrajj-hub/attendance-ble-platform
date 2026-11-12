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
1. **System of Record**: PostgreSQL (hosted on free-tier serverless PostgreSQL via Neon or Supabase) is the authoritative source of truth for user accounts, courses, enrollments, devices, and finalized attendance records.
2. **Ephemeral Live State**: Cloud Firestore (Firebase Spark free plan) is retained exclusively as an ephemeral realtime synchronization layer for active sessions.
3. **Server Authority**: The mobile client is untrusted. Final attendance verification, device signature validation, and recording are executed server-side via a typed FastAPI backend.
4. **Reconciliation**: A background task periodically reconciles active Firestore session records with PostgreSQL.

### Status
Accepted (Amended for $0 Budget)

---

## ADR-0003: AI Model Configuration

### Context
AI model identifiers update periodically. Hardcoding model snapshot strings in application code leads to deprecation issues and lack of environment flexibility.

### Decision
Model identifiers for the AI policy and query assistant are made configurable via environment variables (`AI_MODEL` / `ANTHROPIC_MODEL` / `GEMINI_MODEL`), defaulting to configurable production snapshots. Applications query models dynamically or accept administrator configuration from environment variables.

### Status
Accepted

---

## ADR-0004: $0 Zero-Dollar Cloud & Free-Tier Infrastructure Architecture

### Context
Per confirmed requirement Q9, the monthly cloud budget is strictly **$0.00 / month**. Standard cloud architectures employing AWS RDS, ECS Fargate, EKS, or paid LLM APIs incur monthly recurring charges. The infrastructure must operate entirely within perpetual free tiers while avoiding common cost traps (e.g., Firebase Blaze plan overdrafts, expiring AWS free tiers).

### Options Evaluated

| Layer | Free-Tier Options Evaluated | Selected Architecture | Reason & Trade-offs |
| :--- | :--- | :--- | :--- |
| **Auth & Live Session** | **Firebase Spark** vs. Supabase Realtime | **Firebase Spark Plan** | Codebase already has working Flutter Firebase Auth + Firestore SDK and security rules tests. Free quota (50k reads, 20k writes/day) easily covers a 300-student pilot. |
| **API Compute** | **Google Cloud Run** vs. Render vs. Fly.io | **Google Cloud Run (Free Tier)** | 2M requests/month, 360k GB-sec, 180k vCPU-sec free. Scales to zero (0 cost when idle). Trade-off: ~2-3s cold start latency on first request after idle. |
| **Database** | **Neon Postgres** vs. **Supabase Postgres** | **Neon / Supabase Free Tier** | 0.5 GB free storage, standard PostgreSQL wire protocol compatible with SQLAlchemy/Alembic. Trade-off: auto-suspend on inactivity; backend must use pooled connections with reconnect retry. |
| **Object Storage** | **Cloudflare R2** vs. Local S3 (MinIO) | **Cloudflare R2 (Free Tier)** | 10 GB storage free/month, $0 egress fees. |
| **Edge / Proxy** | Cloudflare Free vs. Raw IP | **Cloudflare Free Tier** | Free DDoS protection, automatic TLS certificates, rate limiting at edge. |
| **Error Tracing** | Sentry Developer vs. CloudWatch | **Sentry Free Tier** | 5,000 events/month, zero cost. |
| **CI/CD** | GitHub Actions | **GitHub Actions** | Unlimited build minutes for public GitHub repositories. |
| **AI / LLM** | Anthropic Claude vs. **Google Gemini API Free Tier** vs. Local Ollama | **Gemini API Free Tier / Delayed** | Delay paid Claude API. In Phase 5, evaluate Google Gemini 1.5/2.0 Flash via Google AI Studio free tier (generous free requests/min with no credit card required) or local quantized LLMs. |

### Cost Trap Mitigations
1. **Firebase Blaze Trap**: Never upgrade the Firebase project to the pay-as-you-go Blaze plan without an enforced hard billing cap. Stay strictly within the Spark plan. (This validates why Cloud Functions were removed earlier).
2. **AWS Free Tier Expiry Trap**: Avoid AWS services that convert to automatic recurring charges after the initial 12-month promotional period.
3. **Database Inactivity Pausing**: Implement connection retries in the FastAPI database engine (`pool_pre_ping=True`) to gracefully handle serverless Postgres cold-wakeups.
4. **Terraform & Kubernetes**: Retain Terraform scripts and Kubernetes manifests strictly as local showcase artifacts (`deploy/k8s/` and local k3s/kind), ensuring zero cloud spend.

### Status
Accepted
