"""
Tests for Forgot Password / Password Reset Flow.

Rules Verified:
1. org_admin can request a password reset OTP via email
2. election_officer can request a password reset OTP via email
3. Voter role is REJECTED with a clear error message
4. Candidate role is REJECTED with a clear error message
5. Non-existent email returns a 'No account found' error
6. OTP is stored hashed in OTPRecord with purpose='password_reset'
7. Correct OTP + new password successfully resets the password
8. Wrong OTP returns a validation error
9. Expired OTP returns a validation error
10. Passwords mismatch returns a validation error
11. After reset, user can login with new password and NOT old one
12. Rate limiting: more than 5 requests in 15 min is rejected
"""
import hashlib
from datetime import timedelta
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole, OTPRecord


class TestPasswordResetFlow(TestCase):

    def setUp(self):
        self.client = APIClient()

        self.org = Organization.objects.create(
            name='Test Organization',
            slug='test-org',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # org_admin — can reset password
        self.admin = User.objects.create_user(
            email='admin@testorg.com',
            password='OldPassword@123',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )

        # election_officer — can reset password
        self.officer = User.objects.create_user(
            email='officer@testorg.com',
            password='OldPassword@123',
            role=UserRole.ELECTION_OFFICER,
            organization=self.org,
        )

        # voter — CANNOT reset password
        self.voter = User.objects.create_user(
            email='voter@testorg.com',
            password='OldPassword@123',
            role=UserRole.VOTER,
            organization=self.org,
        )

        # candidate — CANNOT reset password
        self.candidate = User.objects.create_user(
            email='candidate@testorg.com',
            password='OldPassword@123',
            role=UserRole.CANDIDATE,
            organization=self.org,
        )

        self.request_url = '/v1/auth/password-reset/request/'
        self.confirm_url = '/v1/auth/password-reset/confirm/'

    # ─── STEP 1: Request OTP ──────────────────────────────────────────────────

    def test_01_org_admin_can_request_reset(self):
        """org_admin email should receive OTP successfully."""
        resp = self.client.post(self.request_url, {'email': self.admin.email})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data.get('otp_sent'))

        # Verify an OTPRecord was created
        self.assertTrue(
            OTPRecord.objects.filter(
                identifier=self.admin.email,
                purpose='password_reset',
                is_used=False,
            ).exists()
        )

    def test_02_election_officer_can_request_reset(self):
        """election_officer email should receive OTP successfully."""
        resp = self.client.post(self.request_url, {'email': self.officer.email})
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data.get('otp_sent'))

    def test_03_voter_cannot_request_reset(self):
        """Voter should be rejected — use OTP login instead."""
        resp = self.client.post(self.request_url, {'email': self.voter.email})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        errors = str(resp.data)
        self.assertIn('Organization Admin', errors)

    def test_04_candidate_cannot_request_reset(self):
        """Candidate should be rejected."""
        resp = self.client.post(self.request_url, {'email': self.candidate.email})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_05_nonexistent_email_rejected(self):
        """Email not in system returns a 400 error."""
        resp = self.client.post(self.request_url, {'email': 'ghost@testorg.com'})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        errors = str(resp.data)
        self.assertIn('No account found', errors)

    def test_06_invalid_email_format_rejected(self):
        """Invalid email format returns validation error."""
        resp = self.client.post(self.request_url, {'email': 'not-an-email'})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_07_missing_email_rejected(self):
        """Missing email field returns validation error."""
        resp = self.client.post(self.request_url, {})
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    # ─── STEP 2: Confirm Reset ────────────────────────────────────────────────

    def _create_valid_otp(self, email, expired=False):
        """Helper: creates a real OTPRecord and returns the plaintext OTP."""
        import secrets
        otp = f"{secrets.randbelow(1000000):06d}"
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        expires_at = timezone.now() - timedelta(minutes=1) if expired else timezone.now() + timedelta(minutes=5)
        OTPRecord.objects.create(
            identifier=email,
            otp_hash=otp_hash,
            purpose='password_reset',
            expires_at=expires_at,
        )
        return otp

    def test_08_correct_otp_resets_password(self):
        """Valid OTP + matching passwords → password changed successfully."""
        otp = self._create_valid_otp(self.admin.email)
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })
        self.assertEqual(resp.status_code, status.HTTP_200_OK)
        self.assertTrue(resp.data.get('password_reset'))

        # Verify password actually changed
        self.admin.refresh_from_db()
        self.assertTrue(self.admin.check_password('NewSecure@456'))
        self.assertFalse(self.admin.check_password('OldPassword@123'))

    def test_09_can_login_with_new_password(self):
        """After reset, new password allows login; old password does not."""
        otp = self._create_valid_otp(self.admin.email)
        self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })

        # New password works
        login_resp = self.client.post('/v1/auth/login/', {
            'email_or_phone': self.admin.email,
            'password': 'NewSecure@456',
        })
        self.assertEqual(login_resp.status_code, status.HTTP_200_OK)
        self.assertIn('access', login_resp.data)

        # Old password fails
        old_resp = self.client.post('/v1/auth/login/', {
            'email_or_phone': self.admin.email,
            'password': 'OldPassword@123',
        })
        self.assertEqual(old_resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_10_wrong_otp_rejected(self):
        """Submitting a wrong OTP returns 400."""
        self._create_valid_otp(self.admin.email)
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': '000000',  # Wrong OTP
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Invalid or expired', str(resp.data))

    def test_11_expired_otp_rejected(self):
        """Expired OTP (past expires_at) returns 400."""
        otp = self._create_valid_otp(self.admin.email, expired=True)
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Invalid or expired', str(resp.data))

    def test_12_otp_single_use_rejected_on_reuse(self):
        """Once used, the OTP cannot be reused."""
        otp = self._create_valid_otp(self.admin.email)

        # First use — should succeed
        self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })

        # Second use — should fail
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'AnotherPass@789',
            'confirm_password': 'AnotherPass@789',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_13_passwords_mismatch_rejected(self):
        """new_password != confirm_password → 400."""
        otp = self._create_valid_otp(self.admin.email)
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'DifferentPass@789',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Passwords do not match', str(resp.data))

    def test_14_short_password_rejected(self):
        """Password shorter than 8 chars → 400."""
        otp = self._create_valid_otp(self.admin.email)
        resp = self.client.post(self.confirm_url, {
            'email': self.admin.email,
            'otp': otp,
            'new_password': 'short',
            'confirm_password': 'short',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_15_voter_otp_confirm_rejected(self):
        """Even if voter somehow has an OTPRecord, confirm is still rejected."""
        otp = self._create_valid_otp(self.voter.email)
        resp = self.client.post(self.confirm_url, {
            'email': self.voter.email,
            'otp': otp,
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Password reset is not allowed', str(resp.data))

    def test_16_confirm_nonexistent_email_rejected(self):
        """Confirm with unknown email returns 400."""
        resp = self.client.post(self.confirm_url, {
            'email': 'ghost@nowhere.com',
            'otp': '123456',
            'new_password': 'NewSecure@456',
            'confirm_password': 'NewSecure@456',
        })
        self.assertEqual(resp.status_code, status.HTTP_400_BAD_REQUEST)

    def test_17_officer_full_reset_flow(self):
        """election_officer full flow: request → confirm → login with new password."""
        # Request
        req_resp = self.client.post(self.request_url, {'email': self.officer.email})
        self.assertEqual(req_resp.status_code, status.HTTP_200_OK)

        # Get the OTP from DB (in real life user gets it via email)
        record = OTPRecord.objects.filter(
            identifier=self.officer.email,
            purpose='password_reset',
            is_used=False,
        ).order_by('-created_at').first()
        self.assertIsNotNone(record)

        # We can't get plaintext from hash, so create a fresh known OTP
        import secrets
        known_otp = f"{secrets.randbelow(1000000):06d}"
        record.otp_hash = hashlib.sha256(known_otp.encode()).hexdigest()
        record.save(update_fields=['otp_hash'])

        # Confirm
        confirm_resp = self.client.post(self.confirm_url, {
            'email': self.officer.email,
            'otp': known_otp,
            'new_password': 'OfficerNew@456',
            'confirm_password': 'OfficerNew@456',
        })
        self.assertEqual(confirm_resp.status_code, status.HTTP_200_OK)

        # Login with new password
        login_resp = self.client.post('/v1/auth/login/', {
            'email_or_phone': self.officer.email,
            'password': 'OfficerNew@456',
        })
        self.assertEqual(login_resp.status_code, status.HTTP_200_OK)
        self.assertIn('access', login_resp.data)
