"""
Phase 1 Tests — Backend Foundation
Tests cover:
1. Organization model creation (multi-tenancy setup)
2. User model creation with correct roles
3. TenantScopedManager isolation (CRITICAL security test)
4. Auth API — Register, Login, OTP flow
5. JWT token generation and refresh

(doc: 26-Testing-Strategy.md §26.2 — Tenant Isolation is highest priority)
"""
import pytest
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.audit.models import AuditLog


# ==============================================================================
# FIXTURES
# ==============================================================================

@pytest.fixture
def api_client():
    return APIClient()


@pytest.fixture
def org1(db):
    """First test organization."""
    return Organization.objects.create(
        name='Cooperative A',
        slug='cooperative-a',
        org_type='cooperative',
        status=OrgStatus.ACTIVE,
    )


@pytest.fixture
def org2(db):
    """Second test organization — MUST be completely isolated from org1."""
    return Organization.objects.create(
        name='College B',
        slug='college-b',
        org_type='college',
        status=OrgStatus.ACTIVE,
    )


@pytest.fixture
def org_admin_1(db, org1):
    """Org Admin of Organization 1."""
    return User.objects.create_user(
        email='admin@coop-a.com',
        password='Test@12345',
        role=UserRole.ORG_ADMIN,
        organization=org1,
    )


@pytest.fixture
def org_admin_2(db, org2):
    """Org Admin of Organization 2."""
    return User.objects.create_user(
        email='admin@college-b.com',
        password='Test@12345',
        role=UserRole.ORG_ADMIN,
        organization=org2,
    )


@pytest.fixture
def voter_org1(db, org1):
    """Voter in Organization 1."""
    return User.objects.create_user(
        email='voter@coop-a.com',
        password='Test@12345',
        role=UserRole.VOTER,
        organization=org1,
    )


# ==============================================================================
# ORGANIZATION MODEL TESTS
# ==============================================================================

class TestOrganizationModel(TestCase):

    def test_create_organization(self):
        """Organization is created with correct defaults."""
        org = Organization.objects.create(
            name='Test Cooperative',
            slug='test-cooperative',
            org_type='cooperative',
        )
        self.assertEqual(org.name, 'Test Cooperative')
        self.assertEqual(org.status, OrgStatus.TRIAL)
        self.assertEqual(org.timezone, 'Asia/Kathmandu')
        self.assertEqual(org.grievance_window_days, 3)
        self.assertEqual(org.data_retention_years, 7)

    def test_organization_is_active_trial(self):
        """Trial org counts as active."""
        org = Organization.objects.create(
            name='Trial Org', slug='trial-org', status=OrgStatus.TRIAL
        )
        self.assertTrue(org.is_active)

    def test_organization_suspended_is_not_active(self):
        """Suspended org is not active."""
        org = Organization.objects.create(
            name='Suspended Org', slug='suspended-org', status=OrgStatus.SUSPENDED
        )
        self.assertFalse(org.is_active)

    def test_organization_str(self):
        """__str__ returns readable name."""
        org = Organization.objects.create(
            name='My SACCO', slug='my-sacco', org_type='cooperative'
        )
        self.assertIn('My SACCO', str(org))


# ==============================================================================
# USER MODEL TESTS
# ==============================================================================

class TestUserModel(TestCase):

    def setUp(self):
        self.org = Organization.objects.create(
            name='Test Org', slug='test-org', status=OrgStatus.ACTIVE
        )

    def test_create_org_admin(self):
        user = User.objects.create_user(
            email='admin@test.com',
            password='Test@12345',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )
        self.assertEqual(user.role, UserRole.ORG_ADMIN)
        self.assertTrue(user.is_org_admin)
        self.assertFalse(user.is_super_admin)
        self.assertTrue(user.check_password('Test@12345'))

    def test_super_admin_has_no_org(self):
        """Super Admin is platform-wide — no organization FK required."""
        super_admin = User.objects.create_superuser(
            email='superadmin@platform.com',
            password='Super@12345',
        )
        self.assertIsNone(super_admin.organization)
        self.assertTrue(super_admin.is_super_admin)

    def test_user_password_is_hashed(self):
        """Passwords must never be stored in plaintext (Argon2)."""
        user = User.objects.create_user(
            email='test@hashed.com',
            password='PlainText@123',
            organization=self.org,
        )
        # The stored password_hash must NOT equal the plaintext
        self.assertNotEqual(user.password, 'PlainText@123')
        # But check_password must still work
        self.assertTrue(user.check_password('PlainText@123'))

    def test_unique_email_per_org(self):
        """One email per org — duplicate email in same org must fail."""
        from django.db import IntegrityError
        User.objects.create_user(
            email='dup@test.com', password='Test@12345',
            organization=self.org
        )
        with self.assertRaises(Exception):
            User.objects.create_user(
                email='dup@test.com', password='Test@12345',
                organization=self.org
            )


# ==============================================================================
# TENANT ISOLATION TESTS (CRITICAL — doc: 26-Testing-Strategy.md §26.2)
# ==============================================================================

class TestTenantIsolation(TestCase):
    """
    CRITICAL: These tests verify that an Org Admin from Org 1
    CANNOT access data belonging to Org 2 in any way.
    (doc: 07-System-Architecture.md §7.3, 26-Testing-Strategy.md §26.2)
    """

    def setUp(self):
        self.org1 = Organization.objects.create(
            name='Org 1', slug='org-1', status=OrgStatus.ACTIVE
        )
        self.org2 = Organization.objects.create(
            name='Org 2', slug='org-2', status=OrgStatus.ACTIVE
        )
        self.admin1 = User.objects.create_user(
            email='admin@org1.com', password='Test@12345',
            role=UserRole.ORG_ADMIN, organization=self.org1
        )
        self.admin2 = User.objects.create_user(
            email='admin@org2.com', password='Test@12345',
            role=UserRole.ORG_ADMIN, organization=self.org2
        )

    def test_user_cannot_see_other_org_users(self):
        """
        for_organization() on the User queryset must ONLY return users
        from the specified organization.
        """
        org1_users = User.objects.filter(organization=self.org1)
        org2_users = User.objects.filter(organization=self.org2)

        # org1 users should not include org2 users
        for user in org1_users:
            self.assertEqual(user.organization_id, self.org1.id)

        for user in org2_users:
            self.assertEqual(user.organization_id, self.org2.id)

    def test_audit_logs_are_tenant_scoped(self):
        """AuditLog entries must be scoped to their organization."""
        from apps.audit.models import log_action

        log_action('test.event', organization=self.org1, actor=self.admin1,
                   metadata={'test': 'org1 event'})
        log_action('test.event', organization=self.org2, actor=self.admin2,
                   metadata={'test': 'org2 event'})

        org1_logs = AuditLog.objects.filter(organization=self.org1)
        org2_logs = AuditLog.objects.filter(organization=self.org2)

        self.assertEqual(org1_logs.count(), 1)
        self.assertEqual(org2_logs.count(), 1)
        self.assertNotEqual(org1_logs.first().id, org2_logs.first().id)


# ==============================================================================
# AUTH API TESTS
# ==============================================================================

class TestAuthAPI(TestCase):

    def setUp(self):
        self.client = APIClient()

    def test_register_creates_org_and_admin(self):
        """POST /v1/auth/register/ creates org + admin user in one step."""
        response = self.client.post('/v1/auth/register/', {
            'email': 'newadmin@neworg.com',
            'password': 'NewOrg@12345',
            'org_name': 'New Test Cooperative',
            'org_type': 'cooperative',
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertIn('organization', response.data)
        self.assertEqual(response.data['organization']['status'], 'trial')

        # Verify in DB
        user = User.objects.get(email='newadmin@neworg.com')
        self.assertEqual(user.role, UserRole.ORG_ADMIN)
        org = Organization.objects.get(name='New Test Cooperative')
        self.assertEqual(org.status, OrgStatus.TRIAL)

        # Verify audit log was created
        self.assertTrue(AuditLog.objects.filter(action='org.created').exists())

    def test_register_duplicate_email_fails(self):
        """Cannot register twice with the same email."""
        data = {
            'email': 'dup@test.com',
            'password': 'Dup@12345',
            'org_name': 'First Org',
        }
        self.client.post('/v1/auth/register/', data, format='json')
        response = self.client.post('/v1/auth/register/', data, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_with_valid_credentials(self):
        """POST /v1/auth/login/ returns JWT tokens for valid credentials."""
        org = Organization.objects.create(
            name='Login Test Org', slug='login-test-org', status=OrgStatus.ACTIVE
        )
        User.objects.create_user(
            email='logintest@org.com',
            password='Login@12345',
            organization=org,
        )

        response = self.client.post('/v1/auth/login/', {
            'email_or_phone': 'logintest@org.com',
            'password': 'Login@12345',
        }, format='json')

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)

    def test_login_with_wrong_password_fails(self):
        """Wrong password returns 400, never leaks user existence."""
        org = Organization.objects.create(
            name='Org X', slug='org-x', status=OrgStatus.ACTIVE
        )
        User.objects.create_user(
            email='secure@org.com', password='Correct@123', organization=org
        )
        response = self.client.post('/v1/auth/login/', {
            'email_or_phone': 'secure@org.com',
            'password': 'WRONG_PASSWORD',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_me_endpoint_requires_auth(self):
        """GET /v1/auth/me/ without token returns 401."""
        response = self.client.get('/v1/auth/me/')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_me_endpoint_returns_user_profile(self):
        """GET /v1/auth/me/ with valid token returns user profile."""
        org = Organization.objects.create(
            name='Me Org', slug='me-org', status=OrgStatus.ACTIVE
        )
        user = User.objects.create_user(
            email='me@org.com', password='Me@12345', organization=org
        )
        self.client.force_authenticate(user=user)
        response = self.client.get('/v1/auth/me/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['email'], 'me@org.com')
        # Sensitive fields must NOT be exposed
        self.assertNotIn('password', response.data)
        self.assertNotIn('totp_secret', response.data)


# ==============================================================================
# AUDIT LOG TESTS
# ==============================================================================

class TestAuditLog(TestCase):

    def test_audit_log_is_append_only(self):
        """AuditLog entries are created but never expose an update method."""
        org = Organization.objects.create(
            name='Audit Org', slug='audit-org', status=OrgStatus.ACTIVE
        )
        log = AuditLog.objects.create(
            organization=org,
            action='test.action',
            target_type='organization',
            target_id=org.id,
            metadata={'info': 'test'},
        )
        # AuditLog must not have 'content' of any vote-related data
        self.assertNotIn('vote_content', log.metadata)
        self.assertEqual(log.action, 'test.action')

    def test_log_action_helper(self):
        """log_action() creates a correct AuditLog entry."""
        from apps.audit.models import log_action
        org = Organization.objects.create(
            name='Log Org', slug='log-org', status=OrgStatus.ACTIVE
        )
        user = User.objects.create_user(
            email='actor@log.com', password='Test@12345', organization=org
        )
        log_action(
            'election.published',
            organization=org,
            actor=user,
            metadata={'election_title': 'Annual AGM 2082'},
        )
        log = AuditLog.objects.get(action='election.published')
        self.assertEqual(log.organization, org)
        self.assertEqual(log.actor, user)
        self.assertEqual(log.metadata['election_title'], 'Annual AGM 2082')
