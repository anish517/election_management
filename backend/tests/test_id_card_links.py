"""
ID card pages need a short-lived signed link, issued only to reviewers or to
the card holder; QR codes carry no contact details.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election, ElectionState, Position
from apps.voting.models import VoterRoll
from apps.candidates.models import Candidate


class TestIdCardLinks(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(organization=self.org, title='E', state=ElectionState.NOMINATION_OPEN)
        pos = Position.objects.create(election=self.election, title='President', seats_available=1)
        self.my_cand = Candidate.objects.create(
            election=self.election, position=pos, first_name='Me', email='me@org.test',
            contact_number='9800000001', status='approved',
        )
        self.other_cand = Candidate.objects.create(
            election=self.election, position=pos, first_name='Other', email='other@org.test',
            contact_number='9811111111', status='approved',
        )
        self.my_roll = VoterRoll.objects.create(election=self.election, voter_id='V1', email='me@org.test', phone='9800000001')
        self.other_roll = VoterRoll.objects.create(election=self.election, voter_id='V2', email='other@org.test')
        self.voter = User.objects.create_user(email='me@org.test', password='Voter@12345', organization=self.org,
                                              role=UserRole.VOTER, phone='9800000001')
        self.admin = User.objects.create_user(email='admin@org.test', password='Admin@12345', organization=self.org,
                                              role=UserRole.ORG_ADMIN)
        other_org = Organization.objects.create(name='Other', slug='other')
        self.foreign_admin = User.objects.create_user(email='admin@other.test', password='Admin@12345',
                                                      organization=other_org, role=UserRole.ORG_ADMIN)

    def link(self, kind, target):
        return self.client.post(f'/v1/elections/{self.election.id}/id-card-link/', {'kind': kind, 'id': target}, format='json')

    def test_card_pages_refuse_without_token(self):
        base = f'/v1/elections/{self.election.id}'
        for url in [f'{base}/candidates/{self.my_cand.id}/id_card/', f'{base}/candidates/id_cards_bulk/',
                    f'{base}/voters/{self.my_roll.id}/id_card/', f'{base}/voters/id_cards_bulk/']:
            self.assertEqual(self.client.get(url).status_code, 403, url)
            self.assertEqual(self.client.get(url + '?t=forged').status_code, 403, url)

    def test_candidate_gets_own_card_only(self):
        self.client.force_authenticate(user=self.voter)
        r = self.link('candidate', str(self.my_cand.id))
        self.assertEqual(r.status_code, status.HTTP_200_OK)
        self.client.force_authenticate(user=None)
        page = self.client.get(r.data['url'])
        self.assertEqual(page.status_code, 200)
        self.assertNotIn('me@org.test', page.content.decode())  # not in the QR any more
        self.client.force_authenticate(user=self.voter)
        self.assertEqual(self.link('candidate', str(self.other_cand.id)).status_code, 403)
        self.assertEqual(self.link('candidate', 'bulk').status_code, 403)

    def test_token_is_bound_to_its_card(self):
        self.client.force_authenticate(user=self.voter)
        url = self.link('candidate', str(self.my_cand.id)).data['url']
        token = url.split('?t=')[1]
        other = f'/v1/elections/{self.election.id}/candidates/{self.other_cand.id}/id_card/?t={token}'
        self.client.force_authenticate(user=None)
        self.assertEqual(self.client.get(other).status_code, 403)

    def test_voter_gets_own_voter_card_only(self):
        self.client.force_authenticate(user=self.voter)
        self.assertEqual(self.link('voter', str(self.my_roll.id)).status_code, 200)
        self.assertEqual(self.link('voter', str(self.other_roll.id)).status_code, 403)
        self.assertEqual(self.link('voter', 'bulk').status_code, 403)

    def test_admin_gets_any_card_and_bulk(self):
        self.client.force_authenticate(user=self.admin)
        for kind, target in [('candidate', str(self.other_cand.id)), ('candidate', 'bulk'),
                             ('voter', str(self.other_roll.id)), ('voter', 'bulk')]:
            r = self.link(kind, target)
            self.assertEqual(r.status_code, 200, (kind, target))
            self.client.force_authenticate(user=None)
            self.assertEqual(self.client.get(r.data['url']).status_code, 200, (kind, target))
            self.client.force_authenticate(user=self.admin)

    def test_admin_of_other_org_refused(self):
        self.client.force_authenticate(user=self.foreign_admin)
        self.assertEqual(self.link('candidate', 'bulk').status_code, 403)
        self.assertEqual(self.link('voter', str(self.other_roll.id)).status_code, 403)
