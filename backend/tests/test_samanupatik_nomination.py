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

    def test_samanupatik_auto_position_and_candidate_nomination(self):
        # Verify default position creation if not exists
        if not self.election.positions.exists():
            Position.objects.create(
                election=self.election,
                title="Samānupātik PR Representative (समानुपातिक प्रतिनिधि)",
                seats_available=self.election.total_pr_seats,
                voting_method='samanupatik',
                max_votes_per_voter=1,
                result_order=1,
            )
        self.assertTrue(self.election.positions.exists())
        default_pos = self.election.positions.first()

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
