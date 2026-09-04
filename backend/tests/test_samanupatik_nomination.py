from django.test import TestCase
from rest_framework.exceptions import ValidationError
from apps.users.models import User
from apps.organizations.models import Organization
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.candidates.serializers import CandidateSerializer
from apps.voting.models import VoterRoll, VotingSession
from apps.voting.services import BallotService
from apps.results.services import TallyService

class SamanupatikNominationFlowTestCase(TestCase):
    def setUp(self):
        self.org = Organization.objects.create(name="PR Test Org")
        self.admin = User.objects.create_user(email="admin@pr.com", password="password", organization=self.org, role="org_admin")
        self.voter1 = User.objects.create_user(email="voter1@pr.com", password="password", organization=self.org, role="voter")
        self.voter2 = User.objects.create_user(email="voter2@pr.com", password="password", organization=self.org, role="voter")

        # 1. Create a Pure Samanupatik election
        self.election = Election.objects.create(
            organization=self.org,
            title="Federal PR Election 2026",
            election_type="samanupatik",
            state="voting_open",
            total_pr_seats=5,
            pr_threshold_percent=3.0,
            enable_party=True,
            enable_symbol=True,
            created_by=self.admin
        )
        self.default_pos = Position.objects.create(
            election=self.election,
            title="Samānupātik PR Representative (समानुपातिक प्रतिनिधि)",
            seats_available=self.election.total_pr_seats,
            voting_method='samanupatik',
            max_votes_per_voter=1,
            result_order=1,
        )

    def test_samanupatik_auto_position_and_candidate_nomination(self):
        self.assertTrue(self.election.positions.exists())
        default_pos = self.default_pos

        # 2. Try creating candidate without party affiliation -> must fail
        invalid_serializer = CandidateSerializer(
            data={
                'first_name': 'Candidate',
                'last_name': 'WithoutParty',
                'email': 'c1@pr.com',
                'party_name': '',  # Empty party
                'pr_rank': 1,
            },
            context={'election': self.election}
        )
        with self.assertRaises(ValidationError):
            invalid_serializer.is_valid(raise_exception=True)

        # 3. Create Candidates for Nepali Congress with PR Ranks 1 and 2
        nc1 = Candidate.objects.create(
            election=self.election,
            position=default_pos,
            first_name="Ramesh",
            last_name="Adhikari",
            email="ramesh@nc.com",
            party_name="Nepali congress",
            symbol_name="रुख",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )
        nc2 = Candidate.objects.create(
            election=self.election,
            position=default_pos,
            first_name="Sita",
            last_name="Dahal",
            email="sita@nc.com",
            party_name="Nepali congress",
            symbol_name="रुख",
            pr_rank=2,
            status=NominationStatus.APPROVED
        )

        # Create Candidate for UML with PR Rank 1
        uml1 = Candidate.objects.create(
            election=self.election,
            position=default_pos,
            first_name="Prakash",
            last_name="Shrestha",
            email="prakash@uml.com",
            party_name="UML",
            symbol_name="सूर्य",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )

        # 4. Generate Ballot: verify pure PR party ballot
        ballot = BallotService.generate_ballot(self.election)
        pr_item = next(p for p in ballot if p['id'] == 'pr_ballot')
        self.assertEqual(pr_item['voting_method'], 'samanupatik')
        parties = [c['name'] for c in pr_item['candidates']]
        self.assertIn('Nepali congress', parties)
        self.assertIn('UML', parties)

        # 5. Cast Votes: 2 votes for Nepali Congress
        roll1 = VoterRoll.objects.create(election=self.election, voter_id="V001", email="voter1@pr.com", is_eligible=True)
        token1 = BallotService.start_session(roll1)
        BallotService.cast_vote(token1, {'pr_ballot': ['Nepali congress']})

        roll2 = VoterRoll.objects.create(election=self.election, voter_id="V002", email="voter2@pr.com", is_eligible=True)
        token2 = BallotService.start_session(roll2)
        BallotService.cast_vote(token2, {'pr_ballot': ['Nepali congress']})

        # 6. Tally results
        tally = TallyService.tally_election(self.election)
        self.assertEqual(tally['election_type'], 'samanupatik')
        self.assertEqual(tally['total_valid_party_votes'], 2)
        
        nc_result = next(p for p in tally['party_results'] if p['party_name'] == 'Nepali congress')
        self.assertEqual(nc_result['votes'], 2)
        self.assertEqual(nc_result['vote_percentage'], 100.0)
        self.assertTrue(nc_result['is_qualified'])
        self.assertEqual(nc_result['seats_allocated'], 5)

        # Verify elected candidates follow PR ranking: Rank 1 Ramesh first, Rank 2 Sita second
        elected_names = [e['name'] for e in nc_result['elected_candidates']]
        self.assertEqual(elected_names[0], 'Ramesh Adhikari')
        self.assertEqual(elected_names[1], 'Sita Dahal')

    def test_pr_rank_boundary_validation(self):
        # Election has total_pr_seats = 5. Rank 6 or 0 must fail
        ser_invalid_high = CandidateSerializer(
            data={
                'first_name': 'High',
                'last_name': 'Ranker',
                'email': 'high@rank.com',
                'party_name': 'Nepali congress',
                'pr_rank': 6,
            },
            context={'election': self.election}
        )
        with self.assertRaises(ValidationError) as ctx:
            ser_invalid_high.is_valid(raise_exception=True)
        self.assertIn('pr_rank', str(ctx.exception))

    def test_pr_duplicate_rank_within_same_party_validation(self):
        # Create Rank 1 candidate for NC
        pos = self.default_pos
        Candidate.objects.create(
            election=self.election,
            position=pos,
            first_name="First",
            last_name="Ranker",
            email="first@nc.com",
            party_name="Nepali congress",
            pr_rank=1,
            status=NominationStatus.APPROVED
        )

        # Attempt to create another Rank 1 candidate for NC -> must fail
        ser_duplicate = CandidateSerializer(
            data={
                'first_name': 'Duplicate',
                'last_name': 'Ranker',
                'email': 'duplicate@nc.com',
                'party_name': 'Nepali congress',
                'pr_rank': 1,
            },
            context={'election': self.election}
        )
        with self.assertRaises(ValidationError) as ctx:
            ser_duplicate.is_valid(raise_exception=True)
        self.assertIn('pr_rank', str(ctx.exception))

        # But Rank 1 for a DIFFERENT party (e.g. UML) must succeed!
        ser_uml = CandidateSerializer(
            data={
                'first_name': 'Uml',
                'last_name': 'Leader',
                'email': 'leader@uml.com',
                'party_name': 'UML',
                'pr_rank': 1,
            },
            context={'election': self.election}
        )
        self.assertTrue(ser_uml.is_valid())

    def test_pr_party_candidate_quota_limit(self):
        # Election has total_pr_seats = 5. Nominate 5 candidates for NC (Ranks 1 to 5)
        pos = self.default_pos
        for i in range(1, 6):
            Candidate.objects.create(
                election=self.election,
                position=pos,
                first_name=f"NC_Cand_{i}",
                last_name="Test",
                email=f"nc_{i}@test.com",
                party_name="Nepali congress",
                pr_rank=i,
                status=NominationStatus.APPROVED
            )

        # NC now has 5 candidates (equal to total_pr_seats=5).
        # Attempting to nominate a 6th candidate for NC must fail with party quota limit error
        ser_sixth = CandidateSerializer(
            data={
                'first_name': 'Sixth',
                'last_name': 'Candidate',
                'email': 'sixth@nc.com',
                'party_name': 'Nepali congress',
                'pr_rank': 5,  # even with any rank
            },
            context={'election': self.election}
        )
        with self.assertRaises(ValidationError) as ctx:
            ser_sixth.is_valid(raise_exception=True)
        self.assertIn('party_name', str(ctx.exception))

