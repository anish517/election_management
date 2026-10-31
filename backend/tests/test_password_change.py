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


class TestPasswordChangeEndsOtherSessions(TestCase):
    """Changing the password signs out other devices; this device keeps working."""

    def setUp(self):
        self.client = APIClient()
        self.admin = User.objects.create_superuser(email='platform@ems.test', password='Super@12345')
        self.other = User.objects.create_superuser(email='other@ems.test', password='Other@12345')

    def login(self, email, password):
        r = self.client.post('/v1/auth/login/', {'email_or_phone': email, 'password': password}, format='json')
        self.assertEqual(r.status_code, 200, r.data)
        return r.data['access'], r.data['refresh']

    def me(self, access):
        return self.client.get('/v1/auth/me/', HTTP_AUTHORIZATION=f'Bearer {access}').status_code

    def test_other_devices_are_signed_out(self):
        import time
        laptop_access, laptop_refresh = self.login('platform@ems.test', 'Super@12345')
        phone_access, phone_refresh = self.login('platform@ems.test', 'Super@12345')
        other_access, _ = self.login('other@ems.test', 'Other@12345')
        time.sleep(1.1)  # token "issued at" has whole-second precision

        r = self.client.post('/v1/auth/password/change/', {
            'current_password': 'Super@12345',
            'new_password': 'Brand-New@2026',
            'confirm_password': 'Brand-New@2026',
        }, format='json', HTTP_AUTHORIZATION=f'Bearer {laptop_access}')
        self.assertEqual(r.status_code, 200, r.data)

        # Old tokens (both devices) no longer work, header or ?token= query
        self.assertEqual(self.me(phone_access), 401)
        self.assertEqual(self.me(laptop_access), 401)
        self.assertEqual(self.client.get(f'/v1/auth/me/?token={phone_access}').status_code, 401)
        refresh = self.client.post('/v1/auth/token/refresh/', {'refresh': phone_refresh}, format='json')
        self.assertEqual(refresh.status_code, 401)

        # The device that changed it got fresh tokens that work
        self.assertEqual(self.me(r.data['access']), 200)
        refresh = self.client.post('/v1/auth/token/refresh/', {'refresh': r.data['refresh']}, format='json')
        self.assertEqual(refresh.status_code, 200)

        # Other users are unaffected
        self.assertEqual(self.me(other_access), 200)
