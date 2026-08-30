import uuid
from django.test import TestCase
from django.utils import timezone
from apps.organizations.models import Organization
from apps.users.models import User
from apps.elections.models import Election, Position, VotingMethod, ElectionState
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import Vote
from apps.results.services import TallyService


class ResultsTableTallyTestCase(TestCase):
    """
    Test suite for multi-seat elected determination, tie detection,
    and results table data structures.
    """

    def setUp(self):
        self.org = Organization.objects.create(
            name="Results Test Association",
            slug="results-test-org"
        )
        self.user = User.objects.create_user(
            email="admin@resultstest.com",
            password="Password123!",
            organization=self.org,
            role="org_admin"
        )
        self.election = Election.objects.create(
            organization=self.org,
            title="General Election 2083",
            state=ElectionState.RESULTS_FINAL,
            voting_start_at=timezone.now() - timezone.timedelta(hours=2),
            voting_end_at=timezone.now() + timezone.timedelta(hours=2)
        )

    def test_multi_seat_position_elected_calculation(self):
        """
        In a 3-seat position with 5 candidates, exactly the top 3 candidates
        by votes must be marked as is_elected=True, and remaining as is_elected=False.
        """
        position = Position.objects.create(
            election=self.election,
            title="Central Executive Committee Members",
            seats_available=3,
            voting_method=VotingMethod.MULTI_CHOICE
        )

        candidates = []
        for i in range(1, 6):
            c = Candidate.objects.create(
                election=self.election,
                position=position,
                first_name="Candidate",
                last_name=f"{i}",
                status=NominationStatus.APPROVED
            )
            candidates.append(c)

        # Cast votes:
        # Candidate 1: 50 votes
        # Candidate 2: 40 votes
        # Candidate 3: 30 votes
        # Candidate 4: 20 votes
        # Candidate 5: 10 votes
        c1, c2, c3, c4, c5 = candidates

        for _ in range(50):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(position.id): [str(c1.id)]},
                weight=1.0,
                receipt_hash=uuid.uuid4().hex
            )
        for _ in range(40):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(position.id): [str(c2.id)]},
                weight=1.0,
                receipt_hash=uuid.uuid4().hex
            )
        for _ in range(30):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(position.id): [str(c3.id)]},
                weight=1.0,
                receipt_hash=uuid.uuid4().hex
            )
        for _ in range(20):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(position.id): [str(c4.id)]},
                weight=1.0,
                receipt_hash=uuid.uuid4().hex
            )
        for _ in range(10):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(position.id): [str(c5.id)]},
                weight=1.0,
                receipt_hash=uuid.uuid4().hex
            )

        tally = TallyService.tally_position(position)

        self.assertEqual(tally['seats_available'], 3)
        self.assertFalse(tally['has_tie'])
        self.assertEqual(len(tally['winners']), 3)
        self.assertIn(str(c1.id), tally['winners'])
        self.assertIn(str(c2.id), tally['winners'])
        self.assertIn(str(c3.id), tally['winners'])
        self.assertNotIn(str(c4.id), tally['winners'])
        self.assertNotIn(str(c5.id), tally['winners'])

        # Verify breakdown flags
        bd_map = {item['candidate_id']: item for item in tally['breakdown']}
        self.assertTrue(bd_map[str(c1.id)]['is_elected'])
        self.assertEqual(bd_map[str(c1.id)]['rank'], 1)
        self.assertTrue(bd_map[str(c2.id)]['is_elected'])
        self.assertEqual(bd_map[str(c2.id)]['rank'], 2)
        self.assertTrue(bd_map[str(c3.id)]['is_elected'])
        self.assertEqual(bd_map[str(c3.id)]['rank'], 3)
        self.assertFalse(bd_map[str(c4.id)]['is_elected'])
        self.assertEqual(bd_map[str(c4.id)]['rank'], 4)
        self.assertFalse(bd_map[str(c5.id)]['is_elected'])
        self.assertEqual(bd_map[str(c5.id)]['rank'], 5)

    def test_multi_seat_boundary_tie_detection(self):
        """
        If candidates tie for the last available seat, has_tie must be True
        and tied candidates must have is_tie=True.
        """
        position = Position.objects.create(
            election=self.election,
            title="Vice Presidents",
            seats_available=2,
            voting_method=VotingMethod.MULTI_CHOICE
        )

        c1 = Candidate.objects.create(election=self.election, position=position, first_name="VP", last_name="Alice", status=NominationStatus.APPROVED)
        c2 = Candidate.objects.create(election=self.election, position=position, first_name="VP", last_name="Bob", status=NominationStatus.APPROVED)
        c3 = Candidate.objects.create(election=self.election, position=position, first_name="VP", last_name="Charlie", status=NominationStatus.APPROVED)

        # C1: 100 votes (Clear winner for seat 1)
        # C2: 50 votes (Tied for seat 2)
        # C3: 50 votes (Tied for seat 2)
        for _ in range(100):
            Vote.objects.create(election=self.election, ballot_data={str(position.id): [str(c1.id)]}, weight=1.0, receipt_hash=uuid.uuid4().hex)
        for _ in range(50):
            Vote.objects.create(election=self.election, ballot_data={str(position.id): [str(c2.id)]}, weight=1.0, receipt_hash=uuid.uuid4().hex)
        for _ in range(50):
            Vote.objects.create(election=self.election, ballot_data={str(position.id): [str(c3.id)]}, weight=1.0, receipt_hash=uuid.uuid4().hex)

        tally = TallyService.tally_position(position)

        self.assertEqual(tally['seats_available'], 2)
        self.assertTrue(tally['has_tie'])
        self.assertEqual(tally['winners'], [str(c1.id)])

        bd_map = {item['candidate_id']: item for item in tally['breakdown']}
        self.assertTrue(bd_map[str(c1.id)]['is_elected'])
        self.assertFalse(bd_map[str(c1.id)]['is_tie'])

        self.assertFalse(bd_map[str(c2.id)]['is_elected'])
        self.assertTrue(bd_map[str(c2.id)]['is_tie'])

        self.assertFalse(bd_map[str(c3.id)]['is_elected'])
        self.assertTrue(bd_map[str(c3.id)]['is_tie'])

    def test_nota_exclusion_from_elected(self):
        """
        Even if NOTA gets the highest votes, it must never be marked is_elected=True.
        """
        position = Position.objects.create(
            election=self.election,
            title="President",
            seats_available=1,
            voting_method=VotingMethod.FPTP
        )
        c1 = Candidate.objects.create(election=self.election, position=position, first_name="Candidate", last_name="Ramesh", status=NominationStatus.APPROVED)

        # NOTA gets 50 votes, Ramesh gets 10 votes
        for _ in range(50):
            Vote.objects.create(election=self.election, ballot_data={str(position.id): ['__BOYCOTT__']}, weight=1.0, receipt_hash=uuid.uuid4().hex)
        for _ in range(10):
            Vote.objects.create(election=self.election, ballot_data={str(position.id): [str(c1.id)]}, weight=1.0, receipt_hash=uuid.uuid4().hex)

        tally = TallyService.tally_position(position)
        bd_map = {item['candidate_id']: item for item in tally['breakdown']}

        self.assertIn('__BOYCOTT__', bd_map)
        self.assertFalse(bd_map['__BOYCOTT__']['is_elected'])
        self.assertEqual(bd_map['__BOYCOTT__']['score'], 50.0)
        self.assertTrue(bd_map[str(c1.id)]['is_elected'])
        self.assertEqual(bd_map[str(c1.id)]['score'], 10.0)
