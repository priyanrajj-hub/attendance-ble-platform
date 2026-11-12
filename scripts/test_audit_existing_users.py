"""
Unit Tests for Audit Script (Offline Fixtures)
==============================================
Runs completely offline with zero network or Firebase connection.
Verifies all anomaly detection rules, bypass timestamp window checks,
and admin approval field contract.
"""

import unittest
from datetime import datetime, timezone
import sys
import os

# Ensure scripts folder is in import path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from audit_existing_users import evaluate_user_record, BYPASS_WINDOW_START_UTC, BYPASS_WINDOW_END_UTC


class TestAuditExistingUsers(unittest.TestCase):

    def test_legitimate_verified_student(self):
        """A legitimate student approved by an admin with verifiedBy and verified email should PASS."""
        doc = {
            "email": "student1@ch.students.amrita.edu",
            "role": "student",
            "status": "verified",
            "verifiedBy": "admin_uid_faculty_1",
            "verifiedAt": "2026-07-26T10:00:00Z",
            "createdAt": "2026-07-24T12:00:00Z"
        }
        res = evaluate_user_record(doc, uid="stu_101", auth_email_verified=True)
        self.assertEqual(len(res["anomalies"]), 0, f"Unexpected anomalies: {res['anomalies']}")
        self.assertEqual(res["recommended_action"], "NONE")

    def test_legitimate_pending_student(self):
        """A newly registered student in pending_verification state without verifiedBy should PASS."""
        doc = {
            "email": "student2@ch.students.amrita.edu",
            "role": "student",
            "status": "pending_verification",
            "verifiedBy": None,
            "createdAt": "2026-07-26T08:00:00Z"
        }
        res = evaluate_user_record(doc, uid="stu_102", auth_email_verified=False)
        self.assertEqual(len(res["anomalies"]), 0)
        self.assertEqual(res["recommended_action"], "NONE")

    def test_bypass_window_self_approved_student(self):
        """Account created during commit 135c35a bypass window with status 'verified' and no admin should be FLAGGED."""
        # 2026-07-25 10:44:00 UTC is inside the 10:43:00 to 10:47:54 bypass window
        doc = {
            "email": "bypass_user@ch.students.amrita.edu",
            "role": "student",
            "status": "verified",
            "verifiedBy": None,
            "createdAt": "2026-07-25T10:44:00Z"
        }
        res = evaluate_user_record(doc, uid="stu_bypass_01", auth_email_verified=True)
        self.assertGreater(len(res["anomalies"]), 0)
        self.assertTrue(any("bypass window" in a for a in res["anomalies"]))
        self.assertTrue(any("verifiedBy is null" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")

    def test_verified_status_with_unverified_auth_email(self):
        """User marked verified in Firestore but Firebase Auth email_verified is False should be FLAGGED."""
        doc = {
            "email": "fake_verified@ch.students.amrita.edu",
            "role": "student",
            "status": "verified",
            "verifiedBy": "some_admin",
            "createdAt": "2026-07-20T10:00:00Z"
        }
        res = evaluate_user_record(doc, uid="stu_fake", auth_email_verified=False)
        self.assertTrue(any("Firebase Auth email_verified is FALSE" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")

    def test_role_email_domain_mismatch_student_using_faculty_email(self):
        """A student claiming a faculty email domain should be FLAGGED."""
        doc = {
            "email": "sneaky@ch.amrita.edu",
            "role": "student",
            "status": "pending_verification",
            "createdAt": "2026-07-26T10:00:00Z"
        }
        res = evaluate_user_record(doc, uid="stu_domain_mismatch", auth_email_verified=True)
        self.assertTrue(any("invalid email domain" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")

    def test_role_email_domain_mismatch_faculty_using_student_email(self):
        """A faculty claiming a student email domain should be FLAGGED."""
        doc = {
            "email": "prof_student@ch.students.amrita.edu",
            "role": "faculty",
            "status": "pending_verification",
            "createdAt": "2026-07-26T10:00:00Z"
        }
        res = evaluate_user_record(doc, uid="fac_domain_mismatch", auth_email_verified=True)
        self.assertTrue(any("invalid email domain" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")

    def test_self_approval_anomaly(self):
        """If verifiedBy equals user's own UID, it should be FLAGGED as a self-approval anomaly."""
        doc = {
            "email": "hacker@ch.students.amrita.edu",
            "role": "student",
            "status": "verified",
            "verifiedBy": "uid_attacker_99",
            "createdAt": "2026-07-26T10:00:00Z"
        }
        res = evaluate_user_record(doc, uid="uid_attacker_99", auth_email_verified=True)
        self.assertTrue(any("Self-approval detected" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")

    def test_admin_with_valid_institutional_domain(self):
        """Legitimate admin with @ch.amrita.edu domain should PASS."""
        doc = {
            "email": "sysadmin@ch.amrita.edu",
            "role": "admin",
            "status": "verified",
            "createdAt": "2026-07-01T10:00:00Z"
        }
        res = evaluate_user_record(doc, uid="admin_01", auth_email_verified=True)
        self.assertEqual(len(res["anomalies"]), 0)
        self.assertEqual(res["recommended_action"], "NONE")

    def test_auth_lookup_failure_flagged(self):
        """If Firebase Auth lookup fails (orphaned doc or deleted auth account), it should be FLAGGED."""
        doc = {
            "email": "ghost_user@ch.students.amrita.edu",
            "role": "student",
            "status": "pending_verification",
            "createdAt": "2026-07-26T10:00:00Z"
        }
        res = evaluate_user_record(
            doc,
            uid="ghost_uid_404",
            auth_email_verified=None,
            auth_lookup_error="UserNotFoundError: No user record found for given identifier"
        )
        self.assertTrue(any("Firebase Auth user lookup error" in a for a in res["anomalies"]))
        self.assertEqual(res["recommended_action"], "RESET_TO_PENDING_VERIFICATION")



if __name__ == "__main__":
    unittest.main()
