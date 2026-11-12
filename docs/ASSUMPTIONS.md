# Architecture Assumptions & Working Defaults

This document tracks all non-blocking assumptions, working defaults, and items pending formal institutional confirmation.

---

## 1. Regulatory & Institutional Assumptions

| Item | Working Assumption | Status / Action Required |
| :--- | :--- | :--- |
| **Data Retention** | Attendance records are retained for **1 academic year (3 semesters)**, after which student identifiers are anonymized. System audit logs are retained for **90 days**. | **UNCONFIRMED ASSUMPTION**. <br>⚠️ **Action Required by User**: Confirm these retention timeframes with Amrita Vishwa Vidyapeetham administration / legal cell under India's DPDP Act 2023. |
| **Institution Multi-Tenancy** | Initial launch is single-tenant focused on Amrita Vishwa Vidyapeetham (CCE, Chennai Campus) using `@ch.students.amrita.edu` and `@ch.amrita.edu`. Data schema and API are multi-tenant ready with `institution_id` partition keys. | Accepted working default. |
| **Biometric Privacy** | Local device biometrics (Android BiometricPrompt, iOS Face ID / Touch ID) are strictly local. No raw biometric vectors or templates are transmitted or stored off-device. | Accepted non-negotiable principle (DPDP Act 2023 compliance). |

---

## 2. Infrastructure & $0 Cloud Budget Constraints (Q9 CONFIRMED)

| Item | Working Assumption / Free-Tier Choice | Constraints & Trap Mitigations |
| :--- | :--- | :--- |
| **Monthly Budget** | **$0.00 / month strict ceiling**. | Overrides AWS RDS/ECS defaults. No paid AWS services or auto-charging tiers. |
| **Auth & Live Sync** | **Firebase Spark Plan (Free)**. | Free tier daily quotas (50k reads, 20k writes/day). Cloud Functions are disabled because they require the paid Blaze plan. **Do not upgrade to Blaze without a strict hard billing alert/cap.** |
| **Authoritative Database** | **Neon Postgres (Free Tier)** or **Supabase Postgres (Free Tier)**. | Serverless Postgres (0.5 GB limit). Accounts auto-suspend when idle; cold starts on sleep must be handled with connection retry logic. |
| **API Compute** | **Google Cloud Run (Free Tier)** or Free Container Host. | Cloud Run free tier provides 2M requests/mo, 360k GB-sec, 180k vCPU-sec. Scale-to-zero when idle (zero cost, cold start latency on first check-in). |
| **Object Storage** | **Cloudflare R2 (Free Tier)** or skip exports initially. | 10 GB free storage/month, zero egress fees. Used for student attendance PDF exports. |
| **Edge & Proxy** | **Cloudflare Free Tier**. | Free universal SSL/TLS, basic WAF, and DDoS mitigation. |
| **Error Monitoring** | **Sentry Free Developer Tier**. | 5,000 errors/month, sufficient for pilot class tracing. |
| **CI/CD** | **GitHub Actions (Free for Public Repos)**. | Unlimited minutes on public repos for tests, linting, rules verification. |
| **Showcase Kubernetes / IaC** | **Local k3s / kind / LocalStack**. | Terraform scripts and Kubernetes manifests are maintained strictly as local showcase artifacts; not deployed to paid cloud EKS. |
| **AI / LLM Phase (Phase 5)** | **Delayed until a free tier option is confirmed**. | No paid Claude API key. Candidates for Phase 5: Google Gemini API free tier (via Google AI Studio free quota) or local quantized models for development. |

---

## 3. App Store & Platform Release Assumptions (Q8 CONFIRMED)

| Item | Working Assumption | Status / Action Required |
| :--- | :--- | :--- |
| **Store Accounts** | **No Apple Developer ($99/yr) or Google Play ($25 one-time) accounts currently exist.** | Target **Android first** using direct APK distribution, Firebase App Distribution, or Google Play Internal Sharing. |
| **iOS Development** | Flutter iOS codebase is maintained and compiled in parallel. App Store / TestFlight releases are blocked until an Apple Developer Account is secured. | ⚠️ **Action Required by User**: Inquire with Amrita Vishwa Vidyapeetham IT department to determine if the university possesses an existing Apple Developer Organization/Enterprise account. |
| **Device Integrity** | Android Play Integrity / App Check configured in debug/test mode until production signing keys are bound. | Phase 2 target. |
