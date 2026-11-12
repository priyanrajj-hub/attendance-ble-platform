"""
Audit Script: Scan Firestore for Anomalous Self-Approved Users (Read-Only)
==========================================================================
Identifies Firestore user records that were created or modified during the
bypass period between commit 135c35a and 73f8f97 (or any unverified records
that lack legitimate admin approval metadata).

Operating Rules (Non-Negotiable):
1. STRICTLY READ-ONLY: Contains ZERO .set(), .update(), .delete(), or batch write calls.
2. CREDENTIAL SAFETY: Service account credentials MUST be supplied via the
   environment variable FIREBASE_SERVICE_ACCOUNT_PATH outside the repository.
   NEVER place credentials in the codebase.
3. OUTPUT ISOLATION: Writes reports to audit_report.json (gitignored).
"""

import os
import sys
import json
import re
from datetime import datetime, timezone

# Commit Timestamps for the Bypass Window (IST is UTC+05:30)
# Commit 135c35a: 2026-07-25 16:13:00 +0530 -> 2026-07-25 10:43:00 UTC
# Commit 73f8f97: 2026-07-25 16:17:54 +0530 -> 2026-07-25 10:47:54 UTC
BYPASS_WINDOW_START_UTC = datetime(2026, 7, 25, 10, 43, 0, tzinfo=timezone.utc)
BYPASS_WINDOW_END_UTC = datetime(2026, 7, 25, 10, 47, 54, tzinfo=timezone.utc)

STUDENT_DOMAIN_REGEX = re.compile(r'^[a-zA-Z0-9._-]+@ch\.students\.amrita\.edu$')
FACULTY_DOMAIN_REGEX = re.compile(r'^[a-zA-Z0-9._-]+@ch\.amrita\.edu$')


def parse_timestamp_to_utc(ts_val):
    """Converts Firestore Timestamp, string, or datetime to UTC datetime."""
    if ts_val is None:
        return None
    if isinstance(ts_val, datetime):
        return ts_val if ts_val.tzinfo else ts_val.replace(tzinfo=timezone.utc)
    # Check for Firestore Timestamp object with .to_datetime()
    if hasattr(ts_val, 'to_datetime'):
        dt = ts_val.to_datetime()
        return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    if isinstance(ts_val, str):
        try:
            # ISO format parsing
            dt = datetime.fromisoformat(ts_val.replace('Z', '+00:00'))
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
        except ValueError:
            return None
    return None


def evaluate_user_record(doc_data, uid, auth_email_verified=None):
    """
    Evaluates a single user record against security verification criteria.
    Pure function — runs completely offline for testing without Firebase connection.
    
    Legitimate admin approval contract (from lib/screens/admin_approval_screen.dart):
        users/{uid}.update({
            'status': 'verified',
            'verifiedAt': FieldValue.serverTimestamp(),
            'verifiedBy': adminUid
        })
    """
    email = (doc_data.get('email') or '').strip().lower()
    role = doc_data.get('role')
    status = doc_data.get('status')
    verified_by = doc_data.get('verifiedBy') or doc_data.get('approvedBy')
    verified_at = parse_timestamp_to_utc(doc_data.get('verifiedAt'))
    created_at = parse_timestamp_to_utc(doc_data.get('createdAt'))
    
    anomalies = []

    # Check 1: Role vs Domain Consistency
    if role == 'student':
        if not STUDENT_DOMAIN_REGEX.match(email):
            anomalies.append(f"Student account with invalid email domain: {email}")
    elif role == 'faculty':
        if not FACULTY_DOMAIN_REGEX.match(email):
            anomalies.append(f"Faculty account with invalid email domain: {email}")
    elif role == 'admin':
        if not FACULTY_DOMAIN_REGEX.match(email):
            anomalies.append(f"Admin account without institutional @ch.amrita.edu domain: {email}")
    else:
        anomalies.append(f"Unrecognized user role: '{role}'")

    # Check 2: Auth emailVerified vs Firestore status
    if auth_email_verified is not None:
        if auth_email_verified is False and status == 'verified':
            anomalies.append("User marked 'verified' in Firestore, but Firebase Auth email_verified is FALSE")

    # Check 3: Verified status without legitimate admin approval metadata
    if status == 'verified':
        if not verified_by and role != 'admin':
            anomalies.append(
                "Status is 'verified' but lacks legitimate admin approval signature (verifiedBy is null/empty)"
            )

    # Check 4: Account created during commit 135c35a bypass window without verifiedBy
    if created_at is not None:
        if BYPASS_WINDOW_START_UTC <= created_at <= BYPASS_WINDOW_END_UTC:
            if status == 'verified' and not verified_by:
                anomalies.append(
                    f"Account created exactly during bypass window ({created_at.isoformat()}) with self-approved status"
                )

    # Check 5: Self-approval anomaly (verifiedBy == user's own UID)
    if verified_by and verified_by == uid and role != 'admin':
        anomalies.append("Self-approval detected: verifiedBy matches user's own UID")

    return {
        "uid": uid,
        "email": email,
        "role": role,
        "status": status,
        "verified_by": verified_by,
        "verified_at": verified_at.isoformat() if verified_at else None,
        "created_at": created_at.isoformat() if created_at else None,
        "auth_email_verified": auth_email_verified,
        "anomalies": anomalies,
        "recommended_action": "RESET_TO_PENDING_VERIFICATION" if anomalies else "NONE"
    }


def run_live_audit():
    """Connects to Firestore & Firebase Auth using credentials from environment."""
    cred_path = os.environ.get('FIREBASE_SERVICE_ACCOUNT_PATH')
    if not cred_path or not os.path.isfile(cred_path):
        print("ERROR: FIREBASE_SERVICE_ACCOUNT_PATH environment variable is not set or file does not exist.")
        print("Usage:")
        print("  $env:FIREBASE_SERVICE_ACCOUNT_PATH='C:\\path\\to\\service_account.json'")
        print("  python scripts/audit_existing_users.py")
        sys.exit(1)

    import firebase_admin
    from firebase_admin import credentials, firestore, auth

    if not firebase_admin._apps:
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)

    db = firestore.client()
    print("Connecting to Firestore and streaming users collection (READ-ONLY)...")

    results = []
    users_ref = db.collection('users')
    
    # Read-only stream iterator
    for doc in users_ref.stream():
        uid = doc.id
        doc_data = doc.to_dict() or {}
        
        # Cross-reference Firebase Auth email_verified status
        auth_email_verified = None
        try:
            auth_user = auth.get_user(uid)
            auth_email_verified = auth_user.email_verified
        except Exception:
            pass  # User might exist only in Firestore or Auth lookup failed
            
        audit_res = evaluate_user_record(doc_data, uid, auth_email_verified)
        results.append(audit_res)

    # Write report to local gitignored file
    output_path = "audit_report.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)

    flagged = [r for r in results if r["anomalies"]]
    print("=" * 80)
    print(f"AUDIT COMPLETE (READ-ONLY). Scanned {len(results)} users.")
    print(f"Flagged Anomalous Accounts: {len(flagged)}")
    print(f"Detailed JSON report written to: {os.path.abspath(output_path)}")
    print("=" * 80)
    for r in flagged:
        print(f"UID: {r['uid']} | Email: {r['email']} | Role: {r['role']}")
        for a in r['anomalies']:
            print(f"  [ANOMALY] {a}")
        print(f"  [RECOMMENDATION] {r['recommended_action']}")
        print("-" * 80)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--live":
        run_live_audit()
    else:
        print("Audit script loaded.")
        print("To run live against Firebase project:")
        print("  1. Set FIREBASE_SERVICE_ACCOUNT_PATH environment variable.")
        print("  2. Execute: python scripts/audit_existing_users.py --live")
        print("To run offline unit tests with fixtures:")
        print("  Execute: python -m unittest scripts/test_audit_existing_users.py")
