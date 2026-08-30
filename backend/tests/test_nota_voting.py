"""
Tests for Dynamic Per-Position 'None of the Above' (NOTA) / No Vote Functionality.

Rules Verified:
1. Dynamic Per-Position NOTA Selection: Voters can cast a vote for None of the Above / NOTA
   on any position without referencing a static database candidate record.
2. Tally Isolation: Votes cast for NOTA are tallied separately and do NOT collide with
   actual candidates' tallies.
3. Winner Exclusion: NOTA counts do not cause NOTA to be declared as an official elected candidate.
4. Multi-Position Ballots: Voters can select candidate(s) for Position 1 and NOTA for Position 2 independently.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from django.utils import timezone
from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, VotingSession
from apps.voting.services import BallotService
from apps.results.services import TallyService


class TestDynamicNOTAVoting(TestCase):
    def setUp(self):
        self.client = APIClient()

        # 1. Create Organization
        self.org = Organization.objects.create(
            name='Nepal Engineers Association',
            slug='nea-test',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # 2. Create Voters
        self.voter1 = User.objects.create_user(
            email='voter1@example.com',
            password='Password@123',
            role=UserRole.VOTER,
            organization=self.org,
            phone='9800000001',
        )
        self.voter2 = User.objects.create_user(
            email='voter2@example.com',
            password='Password@123',
            role=UserRole.VOTER,
            organization=self.org,
            phone='9800000002',
        )
        self.voter3 = User.objects.create_user(
            email='voter3@example.com',
            password='Password@123',
            role=UserRole.VOTER,
            organization=self.org,
            phone='9800000003',
        )

        # 3. Create Election in voting_open state
        self.election = Election.objects.create(
            organization=self.org,
            title='Central Executive Committee Election 2083',
            state='voting_open',
            nomination_open_at=timezone.now() - timezone.timedelta(days=5),
            nomination_close_at=timezone.now() - timezone.timedelta(days=2),
            voting_start_at=timezone.now() - timezone.timedelta(hours=2),
            voting_end_at=timezone.now() + timezone.timedelta(days=1),
            allow_boycott=True,
        )

        # 4. Positions
        self.pos_president = Position.objects.create(
            election=self.election,
            title='President',
            seats_available=1,
            voting_method='fptp',
            max_votes_per_voter=1,
            abstain_allowed=True,
            none_of_the_above=True,
            result_order=1,
        )
        self.pos_secretary = Position.objects.create(
            election=self.election,
            title='General Secretary',
            seats_available=1,
            voting_method='fptp',
            max_votes_per_voter=1,
            abstain_allowed=True,
            none_of_the_above=True,
            result_order=2,
        )

        # 5. Candidates (Approved)
        self.cand_pres_1 = Candidate.objects.create(
            election=self.election,
            position=self.pos_president,
            first_name='Dr. Sita',
            last_name='Sharma',
            email='sita.sharma@example.com',
            status=NominationStatus.APPROVED,
        )
        self.cand_pres_2 = Candidate.objects.create(
            election=self.election,
            position=self.pos_president,
            first_name='Er. Rajesh',
            last_name='Karki',
            email='rajesh.karki@example.com',
            status=NominationStatus.APPROVED,
        )
        self.cand_sec_1 = Candidate.objects.create(
            election=self.election,
            position=self.pos_secretary,
            first_name='Adv. Binod',
            last_name='Thapa',
            email='binod.thapa@example.com',
            status=NominationStatus.APPROVED,
        )

        # 6. Register Voters on VoterRoll
        self.roll1 = VoterRoll.objects.create(
            election=self.election,
            email=self.voter1.email,
            first_name='Voter',
            last_name='One',
            is_eligible=True,
        )
        self.roll2 = VoterRoll.objects.create(
            election=self.election,
            email=self.voter2.email,
            first_name='Voter',
            last_name='Two',
            is_eligible=True,
        )
        self.roll3 = VoterRoll.objects.create(
            election=self.election,
            email=self.voter3.email,
            first_name='Voter',
            last_name='Three',
            is_eligible=True,
        )

    def test_cast_nota_vote_and_tally_isolation(self):
        """
        Voter 1 votes for Dr. Sita Sharma (President) & Adv. Binod Thapa (Secretary).
        Voter 2 votes for NOTA (__NO_VOTE__) (President) & Adv. Binod Thapa (Secretary).
        Voter 3 votes for NOTA (__NO_VOTE__) (President) & NOTA (__NO_VOTE__) (Secretary).
        
        Expected Tallies:
        - President:
          - Dr. Sita Sharma: 1.0
          - Er. Rajesh Karki: 0.0
          - NOTA / No Vote: 2.0
          - Total ballots: 3
          - Winner (if finalized): Dr. Sita Sharma (NOTA is never a candidate winner)
        - Secretary:
          - Adv. Binod Thapa: 2.0
          - NOTA / No Vote: 1.0
          - Total ballots: 3
          - Winner (if finalized): Adv. Binod Thapa
        """
        # Voter 1 Casts Vote
        session_token1 = BallotService.start_session(self.roll1)
        ballot1 = {
            str(self.pos_president.id): [str(self.cand_pres_1.id)],
            str(self.pos_secretary.id): [str(self.cand_sec_1.id)],
        }
        receipt1 = BallotService.cast_vote(session_token1, ballot1)
        self.assertTrue(receipt1)

        # Voter 2 Casts Vote with NOTA for President
        session_token2 = BallotService.start_session(self.roll2)
        ballot2 = {
            str(self.pos_president.id): ['__NO_VOTE__'],
            str(self.pos_secretary.id): [str(self.cand_sec_1.id)],
        }
        receipt2 = BallotService.cast_vote(session_token2, ballot2)
        self.assertTrue(receipt2)

        # Voter 3 Casts Vote with NOTA for both
        session_token3 = BallotService.start_session(self.roll3)
        ballot3 = {
            str(self.pos_president.id): ['__NO_VOTE__'],
            str(self.pos_secretary.id): ['__NO_VOTE__'],
        }
        receipt3 = BallotService.cast_vote(session_token3, ballot3)
        self.assertTrue(receipt3)

        # Tally Results
        tally = TallyService.tally_election(self.election)
        self.assertEqual(tally['ballots_cast'], 3)

        # 1. Check President Tally
        pres_res = next(r for r in tally['results'] if r['position_id'] == str(self.pos_president.id))
        self.assertEqual(pres_res['total_valid_ballots'], 3)
        
        breakdown_dict = {b['candidate_id']: b for b in pres_res['breakdown']}
        
        # Sita has 1 vote
        self.assertEqual(breakdown_dict[str(self.cand_pres_1.id)]['score'], 1.0)
        # Rajesh has 0 votes
        self.assertEqual(breakdown_dict[str(self.cand_pres_2.id)]['score'], 0.0)
        # NOTA / Boycott has 2 votes
        self.assertEqual(breakdown_dict['__BOYCOTT__']['score'], 2.0)

        # 2. Check Secretary Tally
        sec_res = next(r for r in tally['results'] if r['position_id'] == str(self.pos_secretary.id))
        self.assertEqual(sec_res['total_valid_ballots'], 3)
        
        sec_breakdown = {b['candidate_id']: b for b in sec_res['breakdown']}
        # Binod has 2 votes
        self.assertEqual(sec_breakdown[str(self.cand_sec_1.id)]['score'], 2.0)
        # NOTA has 1 vote
        self.assertEqual(sec_breakdown['__BOYCOTT__']['score'], 1.0)

        # 3. Verify that NOTA is never in winners list even if it has the highest score
        self.election.state = 'results_final'
        self.election.save()

        final_pres_res = TallyService.tally_position(self.pos_president)
        self.assertNotIn('__BOYCOTT__', final_pres_res['winners'])
        self.assertIn(str(self.cand_pres_1.id), final_pres_res['winners'])

    def test_cast_vote_api_endpoint_accepts_nota(self):
        """Verify API POST /v1/elections/{id}/voting/cast/ endpoint accepts dynamic NOTA payload."""
        self.client.force_authenticate(user=self.voter1)
        
        # Start session via API
        session_resp = self.client.post(f'/v1/elections/{self.election.id}/voting/session/')
        self.assertEqual(session_resp.status_code, status.HTTP_200_OK)
        session_token = session_resp.data['session_token']

        # Cast with NOTA
        cast_payload = {
            'session_token': session_token,
            'ballot_data': {
                str(self.pos_president.id): ['__NO_VOTE__'],
                str(self.pos_secretary.id): [str(self.cand_sec_1.id)],
            }
        }
        cast_resp = self.client.post(f'/v1/elections/{self.election.id}/voting/cast/', cast_payload, format='json')
        self.assertEqual(cast_resp.status_code, status.HTTP_200_OK)
        self.assertTrue('receipt_hash' in cast_resp.data)
