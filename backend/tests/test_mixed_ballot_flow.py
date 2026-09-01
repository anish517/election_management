from django.test import TestCase
from apps.users.models import User
from apps.organizations.models import Organization
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, VotingSession, Vote
from apps.voting.services import BallotService
from apps.results.services import TallyService

class MixedBallotFlowTestCase(TestCase):
    def setUp(self):
        self.org = Organization.objects.create(name="Test Org")
        self.admin = User.objects.create_user(email="admin@test.com", password="password", organization=self.org, role="org_admin")
        self.voter_user = User.objects.create_user(email="voter@test.com", password="password", organization=self.org, role="voter")
        
        self.election = Election.objects.create(
            organization=self.org,
            title="Mixed General Election 2026",
            election_type="mixed",
            state="voting_open",
            total_pr_seats=10,
            pr_threshold_percent=3.0,
            enable_party=True,
            enable_symbol=True,
            created_by=self.admin
        )
        
        self.pos_president = Position.objects.create(
            election=self.election,
            title="President",
            seats_available=1,
            max_votes_per_voter=1
        )
        self.pos_vp = Position.objects.create(
            election=self.election,
            title="Vice President",
            seats_available=1,
            max_votes_per_voter=1
        )
        
        self.c1 = Candidate.objects.create(
            election=self.election,
            position=self.pos_president,
            first_name="Anita",
            last_name="Magar",
            party_name="Nepali congress",
            symbol_name="congo",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )
        self.c2 = Candidate.objects.create(
            election=self.election,
            position=self.pos_president,
            first_name="Bishnu",
            last_name="Sharma",
            party_name="UML",
            symbol_name="yemale",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )
        self.c3 = Candidate.objects.create(
            election=self.election,
            position=self.pos_vp,
            first_name="Suresh",
            last_name="Thapa",
            party_name="RPP",
            symbol_name="rpp",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )
        self.c4 = Candidate.objects.create(
            election=self.election,
            position=self.pos_vp,
            first_name="Kiran",
            last_name="KC",
            party_name="Nepali congress",
            symbol_name="congo",
            pr_rank=2,
            status=NominationStatus.APPROVED
        )
        
        self.roll = VoterRoll.objects.create(
            election=self.election,
            voter_id="V1001",
            email="voter@test.com",
            first_name="Test",
            last_name="Voter",
            is_eligible=True
        )

    def test_mixed_ballot_generation_and_tally(self):
        # 1. Generate Ballot
        ballot = BallotService.generate_ballot(self.election)
        pos_ids = [p['id'] for p in ballot]
        
        self.assertIn(str(self.pos_president.id), pos_ids)
        self.assertIn(str(self.pos_vp.id), pos_ids)
        self.assertIn('pr_ballot', pos_ids)
        
        pr_item = next(p for p in ballot if p['id'] == 'pr_ballot')
        self.assertEqual(pr_item['voting_method'], 'samanupatik')
        party_names = [c['name'] for c in pr_item['candidates']]
        self.assertIn('Nepali congress', party_names)
        self.assertIn('UML', party_names)
        self.assertIn('RPP', party_names)
        
        # 2. Cast Vote with both FPTP and PR party choice
        session_token = BallotService.start_session(self.roll)
        vote_payload = {
            str(self.pos_president.id): [str(self.c1.id)],
            str(self.pos_vp.id): [str(self.c3.id)],
            'pr_ballot': ['Nepali congress'],
        }
        receipt = BallotService.cast_vote(session_token, vote_payload)
        self.assertTrue(receipt)
        
        # 3. Tally results
        tally = TallyService.tally_election(self.election)
        self.assertEqual(tally['election_type'], 'mixed')
        self.assertIn('samanupatik_results', tally)
        
        # Check FPTP results
        pres_res = next(r for r in tally['results'] if r['position_id'] == str(self.pos_president.id))
        self.assertEqual(pres_res['total_valid_ballots'], 1)
        self.assertEqual(pres_res['breakdown'][0]['name'], 'Anita Magar')
        self.assertEqual(pres_res['breakdown'][0]['score'], 1)
        
        # Check Samanupatik PR results
        pr_tally = tally['samanupatik_results']
        self.assertEqual(pr_tally['total_valid_party_votes'], 1)
        nc_res = next(p for p in pr_tally['party_results'] if p['party_name'] == 'Nepali congress')
        self.assertEqual(nc_res['votes'], 1)
        self.assertEqual(nc_res['vote_percentage'], 100.0)
        self.assertTrue(nc_res['is_qualified'])
        self.assertEqual(nc_res['seats_allocated'], 10)
