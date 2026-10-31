"""
Voters and candidates file claims (दाबी) and objections (विरोध) only in their
own name; omission/correction claims are always about their own roll entry.
"""
from datetime import timedelta
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election, ElectionState, Position
from apps.voting.models import VoterRoll, VoterClaim
from apps.candidates.models import Candidate, CandidateObjection


class TestClaimsInOwnName(TestCase):

    def setUp(self):
        self.client = APIClient()
        now = timezone.now()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(
            organization=self.org, title='E', state=ElectionState.NOMINATION_CLOSED,
            first_voter_list_date=now - timedelta(days=2),
            voter_list_claim_date=now + timedelta(days=2),
            nomination_close_at=now - timedelta(hours=1),
            candidacy_claim_date=now + timedelta(days=2),
        )
        self.voter = User.objects.create_user(
            email='me@org.test', password='Voter@12345', organization=self.org,
            role=UserRole.VOTER, phone='9800000001',
        )
        self.my_roll = VoterRoll.objects.create(
            election=self.election, voter_id='V-ME', first_name='Me', last_name='Voter',
            email='me@org.test', phone='9800000001',
        )
        self.other_roll = VoterRoll.objects.create(
            election=self.election, voter_id='V-OTHER', first_name='Other', last_name='Person',
            email='other@org.test',
        )
        self.admin = User.objects.create_user(
            email='admin@org.test', password='Admin@12345', organization=self.org, role=UserRole.ORG_ADMIN,
        )
        pos = Position.objects.create(election=self.election, title='President', seats_available=1)
        self.candidate = Candidate.objects.create(
            election=self.election, position=pos, first_name='Cand', last_name='One', status='submitted',
        )

    def claims_url(self):
        return f'/v1/elections/{self.election.id}/voter-claims/'

    def objections_url(self):
        return f'/v1/elections/{self.election.id}/candidate-objections/'

    def test_voter_claim_uses_own_identity_and_entry(self):
        self.client.force_authenticate(user=self.voter)
        response = self.client.post(self.claims_url(), {
            'claim_type': 'correction',
            'claimant_name': 'Someone Else',
            'claimant_email': 'other@org.test',
            'voter_roll': str(self.other_roll.id),
            'target_voter_name': 'Other Person',
            'description': 'Fix my name',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        claim = VoterClaim.objects.get()
        self.assertEqual(claim.claimant_email, 'me@org.test')
        self.assertNotEqual(claim.claimant_name, 'Someone Else')
        self.assertEqual(claim.voter_roll_id, self.my_roll.id)

    def test_voter_can_object_to_another_voter_in_own_name(self):
        self.client.force_authenticate(user=self.voter)
        response = self.client.post(self.claims_url(), {
            'claim_type': 'objection',
            'claimant_name': 'Someone Else',
            'claimant_email': 'other@org.test',
            'target_voter_name': 'V-OTHER',
            'description': 'Not a member',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        claim = VoterClaim.objects.get()
        self.assertEqual(claim.claimant_email, 'me@org.test')
        self.assertEqual(claim.voter_roll_id, self.other_roll.id)

    def test_voter_cannot_object_to_own_entry(self):
        self.client.force_authenticate(user=self.voter)
        response = self.client.post(self.claims_url(), {
            'claim_type': 'objection',
            'claimant_name': 'x', 'claimant_email': 'me@org.test',
            'target_voter_name': 'V-ME',
            'description': 'self',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_voter_cannot_edit_filed_claim(self):
        self.client.force_authenticate(user=self.voter)
        self.client.post(self.claims_url(), {
            'claim_type': 'correction', 'claimant_name': 'x', 'claimant_email': 'me@org.test',
            'description': 'Fix',
        }, format='json')
        claim = VoterClaim.objects.get()
        response = self.client.patch(f'{self.claims_url()}{claim.id}/', {'claimant_email': 'other@org.test'}, format='json')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_can_file_on_behalf(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.post(self.claims_url(), {
            'claim_type': 'omission',
            'claimant_name': 'Walk-in Member',
            'claimant_email': 'walkin@org.test',
            'description': 'Missing from roll',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        self.assertEqual(VoterClaim.objects.get().claimant_email, 'walkin@org.test')

    def test_candidate_objection_uses_own_identity(self):
        self.candidate.email = 'me@org.test'
        self.candidate.save(update_fields=['email'])
        self.client.force_authenticate(user=self.voter)
        response = self.client.post(self.objections_url(), {
            'candidate': str(self.candidate.id),
            'claimant_name': 'Someone Else',
            'claimant_email': 'other@org.test',
            'objection_reason': 'Not eligible',
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED, response.data)
        objection = CandidateObjection.objects.get()
        self.assertEqual(objection.claimant_email, 'me@org.test')
        self.assertNotEqual(objection.claimant_name, 'Someone Else')


class TestOwnNominationOnlyDuringClaims(TestCase):
    """During the candidacy claim window voters/candidates see only their own nomination."""

    def setUp(self):
        self.client = APIClient()
        now = timezone.now()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(
            organization=self.org, title='E', state=ElectionState.NOMINATION_CLOSED,
            nomination_close_at=now - timedelta(hours=1),
            candidacy_claim_date=now + timedelta(days=2),
        )
        pos = Position.objects.create(election=self.election, title='President', seats_available=1)
        self.mine = Candidate.objects.create(election=self.election, position=pos, first_name='Me', email='me@org.test', status='submitted')
        self.other = Candidate.objects.create(election=self.election, position=pos, first_name='Other', email='other@org.test', status='submitted')
        self.voter = User.objects.create_user(email='me@org.test', password='Voter@12345', organization=self.org, role=UserRole.VOTER)
        self.admin = User.objects.create_user(email='admin@org.test', password='Admin@12345', organization=self.org, role=UserRole.ORG_ADMIN)

    def names_from_list(self):
        r = self.client.get(f'/v1/elections/{self.election.id}/candidates/')
        data = r.data['results'] if isinstance(r.data, dict) else r.data
        return sorted(c['first_name'] for c in data)

    def names_from_election(self):
        r = self.client.get(f'/v1/elections/{self.election.id}/')
        return sorted(c['name'] for p in r.data['positions'] for c in p['candidates'])

    def test_voter_sees_only_own_nomination_in_window(self):
        self.client.force_authenticate(user=self.voter)
        self.assertEqual(self.names_from_list(), ['Me'])
        self.assertEqual(self.names_from_election(), ['Me'])

    def test_voter_sees_everyone_outside_window(self):
        Election.objects.filter(id=self.election.id).update(candidacy_claim_date=timezone.now() - timedelta(minutes=1))
        self.client.force_authenticate(user=self.voter)
        self.assertEqual(self.names_from_list(), ['Me', 'Other'])

    def test_admin_sees_everyone_in_window(self):
        self.client.force_authenticate(user=self.admin)
        self.assertEqual(self.names_from_list(), ['Me', 'Other'])
        self.assertEqual(self.names_from_election(), ['Me', 'Other'])

    def test_voter_cannot_claim_against_other_nomination_in_window(self):
        self.client.force_authenticate(user=self.voter)
        r = self.client.post(f'/v1/elections/{self.election.id}/candidate-objections/', {
            'candidate': str(self.other.id), 'claimant_name': 'x', 'claimant_email': 'me@org.test',
            'objection_reason': 'Not eligible',
        }, format='json')
        self.assertEqual(r.status_code, status.HTTP_403_FORBIDDEN)
        r = self.client.post(f'/v1/elections/{self.election.id}/candidate-objections/', {
            'candidate': str(self.mine.id), 'claimant_name': 'x', 'claimant_email': 'me@org.test',
            'objection_reason': 'Correct my details',
        }, format='json')
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)


class TestNominationSummary(TestCase):

    def setUp(self):
        from apps.elections.models import ElectionRoleAssignment
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.admin = User.objects.create_user(
            email='admin@org.test', password='Admin@12345', organization=self.org, role=UserRole.ORG_ADMIN,
        )
        self.officer = User.objects.create_user(
            email='officer@org.test', password='Off@12345', organization=self.org, role=UserRole.ELECTION_OFFICER,
        )
        self.e1 = Election.objects.create(organization=self.org, title='E1', state=ElectionState.NOMINATION_OPEN)
        self.e2 = Election.objects.create(organization=self.org, title='E2', state=ElectionState.DRAFT)
        ElectionRoleAssignment.objects.create(user=self.officer, election=self.e2, role='election_officer')
        pos = Position.objects.create(election=self.e1, title='President', seats_available=1)
        for st in ['submitted', 'submitted', 'approved', 'rejected', 'draft']:
            Candidate.objects.create(election=self.e1, position=pos, first_name=st, status=st)

    def test_org_admin_sees_all_with_counts(self):
        self.client.force_authenticate(user=self.admin)
        response = self.client.get('/v1/nominations/summary/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        rows = {r['title']: r for r in response.data}
        self.assertEqual(set(rows), {'E1', 'E2'})
        e1 = rows['E1']
        self.assertEqual((e1['pending'], e1['approved'], e1['rejected'], e1['total']), (2, 1, 1, 4))
        self.assertEqual(response.data[0]['title'], 'E1')  # pending first

    def test_officer_sees_only_assigned_elections(self):
        self.client.force_authenticate(user=self.officer)
        response = self.client.get('/v1/nominations/summary/')
        self.assertEqual([r['title'] for r in response.data], ['E2'])

    def test_voter_forbidden(self):
        voter = User.objects.create_user(email='v@org.test', password='V@123456', organization=self.org, role=UserRole.VOTER)
        self.client.force_authenticate(user=voter)
        self.assertEqual(self.client.get('/v1/nominations/summary/').status_code, status.HTTP_403_FORBIDDEN)


class TestNominationPrivacy(TestCase):
    """Voters see only public nomination fields of other candidates."""

    PRIVATE = ('email', 'contact_number', 'date_of_birth', 'address', 'review_notes')

    def setUp(self):
        from apps.candidates.models import CandidateEndorsement
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        # Outside any claim window, so voters see every nomination (public fields only).
        self.election = Election.objects.create(organization=self.org, title='E', state=ElectionState.NOMINATION_OPEN)
        pos = Position.objects.create(election=self.election, title='President', seats_available=1)
        self.other = Candidate.objects.create(
            election=self.election, position=pos, first_name='Other', email='other@org.test',
            contact_number='9811111111', address='Secret Street', review_notes='internal', status='submitted',
            manifesto='Vote for me',
        )
        CandidateEndorsement.objects.create(
            candidate=self.other, endorsement_type='proposer', name='Proposer One',
            phone='9822222222', citizenship_number='12-34', membership_id='M-1',
            signature_url='https://example.test/sig.png',
        )
        self.mine = Candidate.objects.create(
            election=self.election, position=pos, first_name='Me', email='me@org.test',
            contact_number='9800000001', status='submitted',
        )
        self.voter = User.objects.create_user(email='me@org.test', password='Voter@12345', organization=self.org, role=UserRole.VOTER)
        self.admin = User.objects.create_user(email='admin@org.test', password='Admin@12345', organization=self.org, role=UserRole.ORG_ADMIN)

    def rows(self):
        list_resp = self.client.get(f'/v1/elections/{self.election.id}/candidates/')
        data = list_resp.data['results'] if isinstance(list_resp.data, dict) else list_resp.data
        api = {c['first_name']: c for c in data}
        elec = self.client.get(f'/v1/elections/{self.election.id}/').data
        nested = {c['name']: c for p in elec['positions'] for c in p['candidates']}
        return api, nested

    def test_voter_sees_public_fields_of_others(self):
        self.client.force_authenticate(user=self.voter)
        api, nested = self.rows()
        for row in (api['Other'], nested['Other']):
            for field in self.PRIVATE:
                self.assertNotIn(field, row)
            self.assertEqual(row['endorsements'], [
                {'id': row['endorsements'][0]['id'], 'endorsement_type': 'proposer', 'name': 'Proposer One', 'membership_id': 'M-1'}
            ])
        self.assertEqual(api['Other']['manifesto'], 'Vote for me')
        self.assertNotIn('documents', api['Other'])

    def test_candidate_sees_own_full_record(self):
        self.client.force_authenticate(user=self.voter)
        api, nested = self.rows()
        self.assertEqual(api['Me']['email'], 'me@org.test')
        self.assertEqual(nested['Me']['contact_number'], '9800000001')

    def test_admin_sees_full_records(self):
        self.client.force_authenticate(user=self.admin)
        api, nested = self.rows()
        self.assertEqual(api['Other']['address'], 'Secret Street')
        self.assertEqual(nested['Other']['endorsements'][0]['citizenship_number'], '12-34')
