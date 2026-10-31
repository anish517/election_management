"""
Super Admin platform console: cross-tenant organization list and lifecycle edits.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.audit.models import AuditLog


class TestPlatformOrganizations(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.super_admin = User.objects.create_superuser(
            email='platform@ems.test', password='Super@12345',
        )
        self.org1 = Organization.objects.create(name='Alpha Coop', slug='alpha', status=OrgStatus.TRIAL)
        self.org2 = Organization.objects.create(name='Beta Union', slug='beta', status=OrgStatus.ACTIVE)
        self.admin1 = User.objects.create_user(
            email='admin@alpha.test', password='Admin@12345',
            organization=self.org1, role=UserRole.ORG_ADMIN,
        )

    def test_super_admin_lists_all_tenants(self):
        self.client.force_authenticate(user=self.super_admin)
        response = self.client.get('/v1/platform/organizations/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        names = {o['name'] for o in response.data}
        self.assertEqual(names, {'Alpha Coop', 'Beta Union'})
        alpha = next(o for o in response.data if o['name'] == 'Alpha Coop')
        self.assertEqual(alpha['admin_emails'], ['admin@alpha.test'])
        self.assertEqual(alpha['election_count'], 0)

    def test_search_and_status_filters(self):
        self.client.force_authenticate(user=self.super_admin)
        response = self.client.get('/v1/platform/organizations/', {'search': 'beta'})
        self.assertEqual([o['name'] for o in response.data], ['Beta Union'])
        response = self.client.get('/v1/platform/organizations/', {'status': 'trial'})
        self.assertEqual([o['name'] for o in response.data], ['Alpha Coop'])

    def test_org_admin_cannot_access_console(self):
        self.client.force_authenticate(user=self.admin1)
        self.assertEqual(
            self.client.get('/v1/platform/organizations/').status_code,
            status.HTTP_403_FORBIDDEN,
        )
        response = self.client.patch(
            f'/v1/platform/organizations/{self.org2.id}/', {'status': 'suspended'}, format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.org2.refresh_from_db()
        self.assertEqual(self.org2.status, OrgStatus.ACTIVE)

    def test_super_admin_updates_status_only(self):
        self.client.force_authenticate(user=self.super_admin)
        response = self.client.patch(
            f'/v1/platform/organizations/{self.org1.id}/',
            {'status': 'active', 'name': 'Renamed'}, format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.org1.refresh_from_db()
        self.assertEqual(self.org1.status, OrgStatus.ACTIVE)
        self.assertEqual(self.org1.name, 'Alpha Coop')
        self.assertTrue(AuditLog.objects.filter(action='org.platform_updated').exists())
