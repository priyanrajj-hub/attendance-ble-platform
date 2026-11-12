# Architecture Assumptions & Working Defaults

This document tracks all non-blocking assumptions, working defaults, and items pending formal institutional confirmation.

---

## 1. Regulatory & Institutional Assumptions

| Item | Working Assumption | Status / Pending Action |
| :--- | :--- | :--- |
| **Data Retention** | Attendance records are retained for **1 academic year (3 semesters)**, after which student identifiers are anonymized. System audit logs are retained for **90 days**. | **UNCONFIRMED ASSUMPTION**. Requires review and confirmation against Amrita University data governance policy. |
| **Institution Multi-Tenancy** | Initial launch is single-tenant focused on Amrita Vishwa Vidyapeetham (CCE, Chennai Campus) using `@ch.students.amrita.edu` and `@ch.amrita.edu`. Data schema and API are multi-tenant ready with `institution_id` partition keys. | Accepted working default. |
| **Biometric Privacy** | Local device biometrics (Android BiometricPrompt, iOS Face ID / Touch ID) are strictly local. No raw biometric vectors or templates are transmitted or stored off-device. | Accepted non-negotiable principle (DPDP Act 2023 compliance). |

---

## 2. Infrastructure & Cloud Assumptions

| Item | Working Assumption | Status |
| :--- | :--- | :--- |
| **Cloud Provider & Region** | AWS `ap-south-1` (Mumbai) hosting PostgreSQL (RDS) and containerized FastAPI services (ECS Fargate). | Accepted default (Q2). |
| **Deployment Mode** | **Pilot Mode**: ECS Fargate container tasks behind Application Load Balancer. No Kubernetes overhead during pilot. | Accepted default (Q1). |
| **Roster Ingestion** | Course enrollments ingested via faculty-uploaded CSV rosters prior to session launches. | Accepted default (Q3). |
| **Offline Attendance Policy** | Offline check-ins are rejected. Physical presence verification and cryptographic nonce checking require active server connectivity. | Accepted default (Q6). |
| **Session Frequency** | Single attendance check-in window per lecture (configurable, default 5 minutes), with optional manual mid-class re-verification. | Accepted default (Q7). |
| **AI LLM Provider** | Anthropic Claude API using `ANTHROPIC_MODEL` environment variable. Evaluated with fixed toolset, read-only attendance queries, and strict token caps. | Accepted default (Q12). |

---

## 3. Developer & App Store Assumptions

| Item | Working Assumption | Status / Pending Action |
| :--- | :--- | :--- |
| **Developer Accounts** | Initial testing targets **Apple TestFlight Internal** and **Google Play Internal Testing tracks** using available individual/team accounts before proceeding to institutional public release. | Awaiting user account details (Q8). |
| **Monthly Budget Ceiling** | Minimal lean configuration targeting **<$60/month** during initial development. | Awaiting user budget confirmation (Q9). |
| **Language Support** | English primary launch, with Flutter `flutter_localizations` architecture prepared for Tamil and Hindi localization. | Accepted default (Q10). |
