"""
Tests for Single-Position Nomination Enforcement per Election.

Rules Verified:
1. A candidate can successfully nominate for Position A in an election.
2. A candidate attempting to nominate for Position B in the same election is rejected with HTTP 400 and clear error detail.
3. If the candidate's nomination for Position A is WITHDRAWN (or REJECTED), they can subsequently nominate for Position B.
4. Nominating in a different election is completely independent and unaffected.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from django.utils import timezone
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll


class TestCandidateNominationLimit(TestCase):
    def setUp(self):
        self.client = APIClient()

        # Create Organization
        self.org = Organization.objects.create(
            name='Kathmandu Engineering Council',
            slug='kec-test',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # Create Candidate User
        self.candidate_user = User.objects.create_user(
            email='ramesh.sharma@example.com',
            password='Password@123',
            role=UserRole.VOTER,
            organization=self.org,
            phone='9841234567',
        )


        # Create Election 1
        self.election = Election.objects.create(
            organization=self.org,
            title='Annual Executive Board Election 2083',
            state='nomination_open',
            nomination_open_at=timezone.now() - timezone.timedelta(days=1),
            nomination_close_at=timezone.now() + timezone.timedelta(days=5),
        )

        # Positions in Election 1
        self.pos_president = Position.objects.create(
            election=self.election,
            title='President',
            seats_available=1,
            result_order=1,
        )
        self.pos_secretary = Position.objects.create(
            election=self.election,
            title='General Secretary',
            seats_available=1,
            result_order=2,
        )


        # Register voter on voter roll for eligibility
        VoterRoll.objects.create(
            election=self.election,
            email=self.candidate_user.email,
            first_name='Ramesh',
            last_name='Sharma',
            phone=self.candidate_user.phone,
            is_eligible=True,
        )

        # Authenticate client as candidate user
        self.client.force_authenticate(user=self.candidate_user)

    def test_nominate_single_position_success(self):
        """Candidate successfully nominates for Position A (President)."""
        url = f'/v1/elections/{self.election.id}/candidates/'

        payload = {
            'position': str(self.pos_president.id),
            'manifesto': 'Committed to organizational excellence.',
            'endorsements': [],
        }

        response = self.client.post(url, payload, format='json')
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(
            Candidate.objects.filter(
                election=self.election,
                position=self.pos_president,
                email=self.candidate_user.email,
                status=NominationStatus.SUBMITTED,
            ).exists()
        )

    def test_nominate_second_position_in_same_election_blocked(self):
        """
        Candidate already nominated for President attempts to nominate for General Secretary.
        The second attempt MUST fail with HTTP 400 and a descriptive validation error.
        """
        # 1. First nomination for President
        url = f'/v1/elections/{self.election.id}/candidates/'

        first_payload = {
            'position': str(self.pos_president.id),
            'manifesto': 'Presidential manifesto.',
            'endorsements': [],
        }
        resp1 = self.client.post(url, first_payload, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_201_CREATED)

        # 2. Second nomination for General Secretary in the same election
        second_payload = {
            'position': str(self.pos_secretary.id),
            'manifesto': 'Secretarial manifesto.',
            'endorsements': [],
        }
        resp2 = self.client.post(url, second_payload, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_400_BAD_REQUEST)
        
        # Verify error message mentions single position rule
        response_text = str(resp2.data)
        self.assertTrue(
            'already' in response_text.lower() and 'one position' in response_text.lower(),
            f"Expected single position error message, got: {resp2.data}"
        )

        # Verify only 1 candidate record exists in DB
        self.assertEqual(
            Candidate.objects.filter(election=self.election, email=self.candidate_user.email).count(),
            1
        )

    def test_nominate_second_position_after_withdrawal_allowed(self):
        """
        If the candidate withdraws their President nomination, they can then apply for General Secretary.
        """
        # 1. First nomination for President
        url = f'/v1/elections/{self.election.id}/candidates/'

        first_payload = {
            'position': str(self.pos_president.id),
            'manifesto': 'Presidential manifesto.',
            'endorsements': [],
        }
        resp1 = self.client.post(url, first_payload, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_201_CREATED)
        candidate_id = resp1.data['id']

        # 2. Withdraw President candidacy
        withdraw_url = f'/v1/elections/{self.election.id}/candidates/{candidate_id}/withdraw/'
        withdraw_resp = self.client.post(withdraw_url, {'reason': 'Changing candidacy to General Secretary'}, format='json')
        self.assertEqual(withdraw_resp.status_code, status.HTTP_200_OK)

        # 3. Now nominate for General Secretary
        second_payload = {
            'position': str(self.pos_secretary.id),
            'manifesto': 'Secretarial manifesto.',
            'endorsements': [],
        }
        resp2 = self.client.post(url, second_payload, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_201_CREATED)

        # Verify both records exist with appropriate statuses
        cands = Candidate.objects.filter(election=self.election, email=self.candidate_user.email).order_by('created_at')
        self.assertEqual(cands.count(), 2)
        self.assertEqual(cands[0].status, NominationStatus.WITHDRAWN)
        self.assertEqual(cands[1].status, NominationStatus.SUBMITTED)
        self.assertEqual(cands[1].position, self.pos_secretary)

    def test_nominate_in_different_election_allowed(self):
        """
        Candidate nominated in Election 1 can also nominate in Election 2 without collision.
        """
        # 1. Nominate in Election 1
        url1 = f'/v1/elections/{self.election.id}/candidates/'
        resp1 = self.client.post(url1, {'position': str(self.pos_president.id), 'endorsements': []}, format='json')
        self.assertEqual(resp1.status_code, status.HTTP_201_CREATED)

        # 2. Create Election 2
        election2 = Election.objects.create(
            organization=self.org,
            title='Regional Chapter Election 2083',
            state='nomination_open',
            nomination_open_at=timezone.now() - timezone.timedelta(days=1),
            nomination_close_at=timezone.now() + timezone.timedelta(days=5),
        )
        pos2 = Position.objects.create(
            election=election2,
            title='Regional Coordinator',
            seats_available=1,
        )
        VoterRoll.objects.create(
            election=election2,
            email=self.candidate_user.email,
            first_name='Ramesh',
            last_name='Sharma',
            is_eligible=True,
        )

        # 3. Nominate in Election 2
        url2 = f'/v1/elections/{election2.id}/candidates/'
        resp2 = self.client.post(url2, {'position': str(pos2.id), 'endorsements': []}, format='json')
        self.assertEqual(resp2.status_code, status.HTTP_201_CREATED)

