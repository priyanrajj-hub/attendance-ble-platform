"""
Read-Only Audit Script: Scan for Self-Approved Users from Commit 135c35a Bypass
=============================================================================
Purpose:
Identifies user records in Firestore that were created or modified during the
period when commit 135c35a bypassed the admin gate (hardcoded status: 'verified').

Operating Rule:
READ-ONLY. This script ONLY reports findings. It does NOT modify or write any
data to production without explicit administrator confirmation.
"""

import sys
import os
import json
from datetime import datetime

def audit_user_document(user_data, user_id):
    """
    Evaluates a user record against security verification criteria.
    Flags records that have status == 'verified' but lack legitimate admin approval metadata.
    """
    status = user_data.get('status')
    role = user_data.get('role')
    verified_by = user_data.get('verifiedBy') or user_data.get('approvedBy')
    created_at = user_data.get('createdAt')
    
    anomalies = []
    
    # Check 1: User marked 'verified' without an admin identifier
    if status == 'verified':
        if not verified_by and role != 'admin':
            anomalies.append("Status is 'verified' but lacks admin approval signature (verifiedBy / approvedBy is null)")
            
    # Check 2: Student accounts claiming unverified admin status
    if role == 'admin' and not user_data.get('email', '').endswith('@ch.amrita.edu'):
        anomalies.append("User holds 'admin' role without faculty/institutional email domain")
        
    return {
        "uid": user_id,
        "email": user_data.get('email', 'UNKNOWN'),
        "role": role,
        "status": status,
        "created_at": str(created_at) if created_at else "UNKNOWN",
        "verified_by": verified_by,
        "anomalies": anomalies,
        "recommended_action": "RESET_TO_PENDING_VERIFICATION" if anomalies else "NONE"
    }

def print_audit_report(results):
    print("=" * 80)
    print("FIRESTORE USER VERIFICATION AUDIT REPORT (READ-ONLY)")
    print("=" * 80)
    flagged = [r for r in results if r['anomalies']]
    
    print(f"Total Users Audited: {len(results)}")
    print(f"Flagged Anomalous Accounts: {len(flagged)}")
    print("-" * 80)
    
    for item in flagged:
        print(f"UID: {item['uid']} | Email: {item['email']} | Role: {item['role']}")
        print(f"  Status: {item['status']} | Verified By: {item['verified_by']}")
        for anomaly in item['anomalies']:
            print(f"  [ANOMALY] {anomaly}")
        print(f"  [PROPOSAL] {item['recommended_action']}")
        print("-" * 80)
        
    if not flagged:
        print("No anomalous self-approved user accounts detected.")
    else:
        print("\nPROPOSED ACTION:")
        print(f"Found {len(flagged)} accounts that appear self-approved during commit 135c35a.")
        print("To reset these accounts, run the migration script with explicit confirmation.")
    print("=" * 80)

if __name__ == "__main__":
    print("Script template ready. Connect with firebase-admin credentials to execute in staging/production.")
