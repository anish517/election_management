"""
One voter, one vote: a ballot can't be cast twice for the same voter, a
voter can't give one candidate several votes in a position, and kiosk
ballots get the same validation as online / ballot-link ballots.
"""
from django.test import TestCase
from rest_framework.test import APIClient
from apps.organizations.models import Organization
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote
from apps.voting.serializers import CastVoteSerializer
from apps.voting.services import BallotService


class TestOneVotePerVoter(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.election = Election.objects.create(organization=self.org, title='Board', state='voting_open')
        # Two seats, so a voter may pick two different candidates.
        self.pos = Position.objects.create(election=self.election, title='Member', seats_available=2,
                                           max_votes_per_voter=2)
        self.a = Candidate.objects.create(election=self.election, position=self.pos, first_name='A',
                                          status=NominationStatus.APPROVED)
        self.b = Candidate.objects.create(election=self.election, position=self.pos, first_name='B',
                                          status=NominationStatus.APPROVED)
        self.roll = VoterRoll.objects.create(election=self.election, voter_id='V1', email='v@org.test')

    def ballot(self, *cands):
        return {str(self.pos.id): [str(c.id) for c in cands]}

    def test_same_candidate_twice_is_rejected(self):
        s = CastVoteSerializer(data={'ballot_data': self.ballot(self.a, self.a)}, context={'election': self.election})
        self.assertFalse(s.is_valid())
        ok = CastVoteSerializer(data={'ballot_data': self.ballot(self.a, self.b)}, context={'election': self.election})
        self.assertTrue(ok.is_valid(), ok.errors)

    def test_session_cannot_be_reused(self):
        token = BallotService.start_session(self.roll)
        BallotService.cast_vote(token, self.ballot(self.a))
        with self.assertRaises(ValueError):
            BallotService.cast_vote(token, self.ballot(self.b))
        self.assertEqual(Vote.objects.filter(election=self.election).count(), 1)

    def test_no_new_session_after_voting(self):
        # Only one session per voter can exist (unique), and none after voting.
        token = BallotService.start_session(self.roll)
        BallotService.cast_vote(token, self.ballot(self.a))
        self.roll.refresh_from_db()  # each request loads the roll fresh
        with self.assertRaises(ValueError):
            BallotService.start_session(self.roll)
        self.assertEqual(Vote.objects.filter(election=self.election).count(), 1)

    def kiosk_cast(self, token, ballot):
        return self.client.post('/v1/voting/kiosk/cast/', {'session_token': token, 'ballot_data': ballot}, format='json')

    def test_kiosk_ballot_is_validated(self):
        token = BallotService.start_session(self.roll)
        self.assertEqual(self.kiosk_cast(token, self.ballot(self.a, self.a)).status_code, 400)
        c = Candidate.objects.create(election=self.election, position=self.pos, first_name='C',
                                     status=NominationStatus.APPROVED)
        self.assertEqual(self.kiosk_cast(token, self.ballot(self.a, self.b, c)).status_code, 400)
        self.assertEqual(Vote.objects.count(), 0)
        self.assertEqual(self.kiosk_cast(token, self.ballot(self.a, self.b)).status_code, 200)
        self.assertEqual(self.kiosk_cast(token, self.ballot(self.a)).status_code, 400)
        self.assertEqual(Vote.objects.filter(election=self.election).count(), 1)
        self.roll.refresh_from_db()
        self.assertTrue(self.roll.has_voted)
