"""
Self-service password change (POST /v1/auth/password/change/) and the
rule that Super Admins never belong to an organization.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.audit.models import AuditLog

URL = '/v1/auth/password/change/'


class TestPasswordChange(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.super_admin = User.objects.create_superuser(
            email='platform@ems.test', password='Super@12345',
        )

    def test_super_admin_changes_password(self):
        self.client.force_authenticate(user=self.super_admin)
        response = self.client.post(URL, {
            'current_password': 'Super@12345',
            'new_password': 'Brand-New@2026',
            'confirm_password': 'Brand-New@2026',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.super_admin.refresh_from_db()
        self.assertTrue(self.super_admin.check_password('Brand-New@2026'))
        self.assertTrue(AuditLog.objects.filter(action='user.password_changed').exists())

    def test_wrong_current_password_rejected(self):
        self.client.force_authenticate(user=self.super_admin)
        response = self.client.post(URL, {
            'current_password': 'nope',
            'new_password': 'Brand-New@2026',
            'confirm_password': 'Brand-New@2026',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.super_admin.refresh_from_db()
        self.assertTrue(self.super_admin.check_password('Super@12345'))

    def test_mismatch_and_weak_password_rejected(self):
        self.client.force_authenticate(user=self.super_admin)
        for new, confirm in [('Brand-New@2026', 'Different@2026'), ('password', 'password')]:
            response = self.client.post(URL, {
                'current_password': 'Super@12345',
                'new_password': new,
                'confirm_password': confirm,
            }, format='json')
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_voter_cannot_change_password(self):
        org = Organization.objects.create(name='Org', slug='org')
        voter = User.objects.create_user(
            email='voter@org.test', password='Voter@12345', organization=org, role=UserRole.VOTER,
        )
        self.client.force_authenticate(user=voter)
        response = self.client.post(URL, {
            'current_password': 'Voter@12345',
            'new_password': 'Brand-New@2026',
            'confirm_password': 'Brand-New@2026',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_anonymous_rejected(self):
        response = self.client.post(URL, {}, format='json')
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_super_admin_never_has_organization(self):
        org = Organization.objects.create(name='Org', slug='org')
        user = User.objects.create_user(
            email='promoted@org.test', password='Voter@12345', organization=org, role=UserRole.VOTER,
        )
        user.role = UserRole.SUPER_ADMIN
        user.save()
        user.refresh_from_db()
        self.assertIsNone(user.organization_id)

    def test_super_admin_org_cleared_with_update_fields(self):
        org = Organization.objects.create(name='Org2', slug='org2')
        user = User.objects.create_user(
            email='promoted2@org.test', password='Voter@12345', organization=org, role=UserRole.VOTER,
        )
        user.role = UserRole.SUPER_ADMIN
        user.save(update_fields=['role'])
        user.refresh_from_db()
        self.assertIsNone(user.organization_id)
