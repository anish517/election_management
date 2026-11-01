"""
Platform overview, organization prefix as public URL, voter list lock after
the final voter list, and WhatsApp ballot links during voting.
"""
from datetime import timedelta
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from apps.organizations.models import Organization
from apps.elections.models import Election
from apps.users.models import User
from apps.voting.models import VoterRoll
from apps.voting.views import whatsapp_number


def make_user(email, role, org=None):
    return User.objects.create_user(email=email, password='Passw0rd!x', role=role, organization=org)


class TestPlatformOverview(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org', prefix='ORG')
        Election.objects.create(organization=self.org, title='Running', state='voting_open')
        Election.objects.create(organization=self.org, title='Nominating', state='nomination_open')
        Election.objects.create(organization=self.org, title='Done', state='results_final')
        Election.objects.create(organization=self.org, title='Draft', state='draft')

    def test_super_admin_sees_totals_and_lists(self):
        self.client.force_authenticate(make_user('root@x.test', 'super_admin'))
        res = self.client.get('/v1/platform/overview/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['stats'], {'organizations': 1, 'elections': 4, 'active_elections': 2})
        self.assertEqual({e['title'] for e in res.data['running_elections']}, {'Running', 'Nominating'})
        self.assertEqual([e['title'] for e in res.data['past_elections']], ['Done'])
        self.assertEqual(res.data['running_elections'][0]['organization']['prefix'], 'ORG')
        self.assertEqual(len(res.data['organizations']), 1)

    def test_org_admin_is_refused(self):
        self.client.force_authenticate(make_user('a@x.test', 'org_admin', self.org))
        self.assertEqual(self.client.get('/v1/platform/overview/').status_code, 403)


class TestOrganizationPrefix(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org', prefix='SOC')
        Election.objects.create(organization=self.org, title='Public', state='published')
        Election.objects.create(organization=self.org, title='Hidden', state='draft')

    def test_public_page_by_prefix_any_case(self):
        res = self.client.get('/v1/public/organizations/soc/')
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data['name'], 'Org')
        self.assertEqual([e['title'] for e in res.data['elections']], ['Public'])
        self.assertNotIn('payment_settings', res.data)
        self.assertEqual(self.client.get('/v1/public/organizations/nope/').status_code, 404)

    def test_prefix_must_be_unique_and_url_safe(self):
        other = Organization.objects.create(name='Other', slug='other')
        self.client.force_authenticate(make_user('a@x.test', 'org_admin', other))
        for bad in ('soc', 'has space', 'admin'):
            res = self.client.patch('/v1/organization/', {'prefix': bad}, format='json')
            self.assertEqual(res.status_code, 400, bad)
        res = self.client.patch('/v1/organization/', {'prefix': 'NMB-2'}, format='json')
        self.assertEqual(res.status_code, 200, res.data)
        # Saving your own prefix again is fine.
        self.client.force_authenticate(make_user('b@x.test', 'org_admin', self.org))
        self.assertEqual(self.client.patch('/v1/organization/', {'prefix': 'SOC'}, format='json').status_code, 200)


class TestVoterListLock(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(
            organization=self.org, title='E', state='nomination_open',
            final_voter_list_date=timezone.now() - timedelta(hours=1),
        )
        self.roll = VoterRoll.objects.create(
            election=self.election, voter_id='V1', first_name='Ram', last_name='Thapa',
            email='old@x.test', phone='9800000000',
        )
        self.url = f'/v1/elections/{self.election.id}/voters/'
        self.admin = make_user('a@x.test', 'org_admin', self.org)
        self.officer = make_user('o@x.test', 'election_officer', self.org)

    def test_admin_can_fix_contact_details_only(self):
        self.client.force_authenticate(self.admin)
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'email': 'new@x.test', 'phone': '9811111111'}, format='json')
        self.assertEqual(res.status_code, 200, res.data)
        self.roll.refresh_from_db()
        self.assertEqual((self.roll.email, self.roll.phone), ('new@x.test', '9811111111'))
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'first_name': 'Shyam'}, format='json')
        self.assertEqual(res.status_code, 403)
        # Resending unchanged fields alongside the contact change is allowed.
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'first_name': 'Ram', 'phone': '9822222222'}, format='json')
        self.assertEqual(res.status_code, 200, res.data)

    def test_officer_cannot_edit_after_final_list(self):
        self.client.force_authenticate(self.officer)
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'email': 'new@x.test'}, format='json')
        self.assertEqual(res.status_code, 403)

    def test_no_adding_or_removing_after_final_list(self):
        self.client.force_authenticate(self.admin)
        res = self.client.post(self.url, {'voter_id': 'V2', 'first_name': 'A', 'last_name': 'B'}, format='json')
        self.assertEqual(res.status_code, 403)
        self.assertEqual(self.client.delete(f'{self.url}{self.roll.id}/').status_code, 403)

    def test_editing_is_open_before_final_list(self):
        self.election.final_voter_list_date = timezone.now() + timedelta(days=1)
        self.election.save()
        self.client.force_authenticate(self.officer)
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'first_name': 'Shyam'}, format='json')
        self.assertEqual(res.status_code, 200, res.data)

    def test_voters_cannot_edit_the_roll(self):
        self.election.final_voter_list_date = None
        self.election.save()
        self.client.force_authenticate(make_user('v@x.test', 'voter', self.org))
        res = self.client.patch(f'{self.url}{self.roll.id}/', {'first_name': 'X'}, format='json')
        self.assertEqual(res.status_code, 403)


class TestWhatsAppBallotLink(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(organization=self.org, title='E', state='voting_open')
        self.roll = VoterRoll.objects.create(
            election=self.election, voter_id='V1', first_name='Ram', last_name='Thapa', phone='98-0000-0000',
        )
        self.url = f'/v1/elections/{self.election.id}/voters/{self.roll.id}/ballot-link/'

    def test_officer_gets_whatsapp_link(self):
        self.client.force_authenticate(make_user('o@x.test', 'election_officer', self.org))
        res = self.client.post(self.url)
        self.assertEqual(res.status_code, 200, res.data)
        self.assertTrue(res.data['whatsapp_url'].startswith('https://wa.me/9779800000000?text='))
        self.roll.refresh_from_db()
        self.assertIn(self.roll.direct_ballot_token, res.data['direct_link_url'])
        # Asking again reuses the live link.
        self.assertEqual(self.client.post(self.url).data['direct_link_url'], res.data['direct_link_url'])

    def test_only_during_voting_and_only_staff(self):
        self.client.force_authenticate(make_user('v@x.test', 'voter', self.org))
        self.assertEqual(self.client.post(self.url).status_code, 403)
        self.client.force_authenticate(make_user('a@x.test', 'org_admin', self.org))
        self.election.state = 'voting_closed'
        self.election.save()
        self.assertEqual(self.client.post(self.url).status_code, 400)

    def test_already_voted_is_refused(self):
        self.roll.has_voted = True
        self.roll.save()
        self.client.force_authenticate(make_user('a@x.test', 'org_admin', self.org))
        self.assertEqual(self.client.post(self.url).status_code, 400)

    def test_number_normalisation(self):
        self.assertEqual(whatsapp_number('9841234567'), '9779841234567')
        self.assertEqual(whatsapp_number('+977 984-1234567'), '9779841234567')
        self.assertEqual(whatsapp_number('0061 412 345 678'), '61412345678')
        self.assertEqual(whatsapp_number('12345'), '')
