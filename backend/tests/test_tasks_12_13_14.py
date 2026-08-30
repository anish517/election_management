import uuid
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election, Position, VotingMethod, ElectionState
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote
from apps.voting.services import BallotService
from apps.results.services import TallyService


class UncontestedAndScopingTestCase(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(
            name="Apex Engineering Society",
            slug="apex-eng-society"
        )
        
        # Admin user
        self.admin = User.objects.create_user(
            email="admin@apex.org",
            password="Password123!",
            organization=self.org,
            role=UserRole.ORG_ADMIN
        )

        # Voters
        self.voter_a = User.objects.create_user(
            email="voter_a@apex.org",
            password="Password123!",
            organization=self.org,
            role=UserRole.VOTER,
            phone="9841000001"
        )
        self.voter_b = User.objects.create_user(
            email="voter_b@apex.org",
            password="Password123!",
            organization=self.org,
            role=UserRole.VOTER,
            phone="9841000002"
        )

        # Election 1 (Civil Dept Election)
        self.election_1 = Election.objects.create(
            organization=self.org,
            title="Civil Department Election 2083",
            state=ElectionState.VOTING_OPEN,
            show_uncontested_on_notice=True,
            show_uncontested_on_ballot=False,
            show_uncontested_in_results=True,
        )

        # Election 2 (Computer Dept Election)
        self.election_2 = Election.objects.create(
            organization=self.org,
            title="Computer Department Election 2083",
            state=ElectionState.VOTING_OPEN,
        )

        # Enroll voter_a ONLY in Election 1
        self.roll_1a = VoterRoll.objects.create(
            election=self.election_1,
            voter_id="CIVIL-001",
            first_name="Aarav",
            last_name="Sharma",
            email=self.voter_a.email,
            phone=self.voter_a.phone,
            is_eligible=True
        )

        # Enroll voter_b ONLY in Election 2
        self.roll_2b = VoterRoll.objects.create(
            election=self.election_2,
            voter_id="COMP-001",
            first_name="Bikash",
            last_name="Thapa",
            email=self.voter_b.email,
            phone=self.voter_b.phone,
            is_eligible=True
        )

    # --------------------------------------------------------------------------
    # Task 12: Uncontested ("Nirbirod" / निर्विरोध) Tests
    # --------------------------------------------------------------------------
    def test_uncontested_position_tally_and_elected_status(self):
        """
        If approved candidate count <= seats_available, position is uncontested
        and all approved candidates are marked is_elected=True in results state.
        """
        self.election_1.state = ElectionState.RESULTS_FINAL
        self.election_1.save()

        pos = Position.objects.create(
            election=self.election_1,
            title="President (अध्यक्ष)",
            seats_available=1,
            voting_method=VotingMethod.FPTP
        )
        cand = Candidate.objects.create(
            election=self.election_1,
            position=pos,
            first_name="Ramesh",
            last_name="Khadka",
            status=NominationStatus.APPROVED
        )

        tally = TallyService.tally_position(pos)
        self.assertTrue(tally['is_uncontested'])
        self.assertEqual(len(tally['breakdown']), 1)
        self.assertTrue(tally['breakdown'][0]['is_elected'])
        self.assertTrue(tally['breakdown'][0]['is_uncontested'])
        self.assertEqual(tally['breakdown'][0]['rank'], 1)

    def test_uncontested_position_ballot_exclusion(self):
        """
        When show_uncontested_on_ballot=False, uncontested positions are excluded
        from ballot rendering. When True, they are included.
        """
        pos = Position.objects.create(
            election=self.election_1,
            title="Treasurer (कोषाध्यक्ष)",
            seats_available=1,
            voting_method=VotingMethod.FPTP
        )
        Candidate.objects.create(
            election=self.election_1,
            position=pos,
            first_name="Sita",
            last_name="Adhikari",
            status=NominationStatus.APPROVED
        )

        # Case 1: show_uncontested_on_ballot is False
        self.election_1.show_uncontested_on_ballot = False
        self.election_1.save()
        ballot_data = BallotService.generate_ballot(self.election_1)
        self.assertEqual(len(ballot_data), 0)

        # Case 2: show_uncontested_on_ballot is True
        self.election_1.show_uncontested_on_ballot = True
        self.election_1.save()
        ballot_data = BallotService.generate_ballot(self.election_1)
        self.assertEqual(len(ballot_data), 1)
        self.assertTrue(ballot_data[0]['is_uncontested'])

    # --------------------------------------------------------------------------
    # Task 13: Digital ID Card Tests
    # --------------------------------------------------------------------------
    def test_voter_id_card_generation_endpoint(self):
        self.client.force_authenticate(user=self.admin)
        url = f"/v1/elections/{self.election_1.id}/voters/{self.roll_1a.id}/id_card/"
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        content = response.content.decode('utf-8')
        self.assertIn("Aarav Sharma", content)
        self.assertIn("CIVIL-001", content)
        self.assertIn("VOTER ID", content)
        self.assertIn("Civil Department Election 2083", content)

    def test_candidate_id_card_generation_endpoint(self):
        self.client.force_authenticate(user=self.admin)
        pos = Position.objects.create(
            election=self.election_1,
            title="Secretary",
            seats_available=1
        )
        cand = Candidate.objects.create(
            election=self.election_1,
            position=pos,
            first_name="Kiran",
            last_name="KC",
            status=NominationStatus.APPROVED
        )
        url = f"/v1/elections/{self.election_1.id}/candidates/{cand.id}/id_card/"
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        content = response.content.decode('utf-8')
        self.assertIn("Kiran KC", content)
        self.assertIn("Secretary", content)
        self.assertIn("CANDIDATE ID", content)

    def test_bulk_voter_id_cards_endpoint(self):
        self.client.force_authenticate(user=self.admin)
        url = f"/v1/elections/{self.election_1.id}/voters/id_cards_bulk/"
        response = self.client.get(url)
        self.assertEqual(response.status_code, 200)
        content = response.content.decode('utf-8')
        self.assertIn("CIVIL-001", content)
        self.assertIn("Aarav Sharma", content)

    def test_unauthenticated_browser_access_to_id_cards(self):
        """
        Opening ID cards or bulk ID cards in a new browser tab sends NO Bearer token.
        Both endpoints MUST return 200 OK without 401 Unauthorized.
        """
        unauthenticated_client = APIClient()

        # 1. Bulk candidate ID cards
        pos = Position.objects.create(
            election=self.election_1,
            title="Vice President",
            seats_available=1
        )
        cand = Candidate.objects.create(
            election=self.election_1,
            position=pos,
            first_name="Sunita",
            last_name="Gurung",
            status=NominationStatus.APPROVED
        )
        cand_bulk_url = f"/v1/elections/{self.election_1.id}/candidates/id_cards_bulk/"
        cand_bulk_res = unauthenticated_client.get(cand_bulk_url)
        self.assertEqual(cand_bulk_res.status_code, 200)
        self.assertIn("Sunita Gurung", cand_bulk_res.content.decode('utf-8'))

        # 2. Individual candidate ID card
        cand_single_url = f"/v1/elections/{self.election_1.id}/candidates/{cand.id}/id_card/"
        cand_single_res = unauthenticated_client.get(cand_single_url)
        self.assertEqual(cand_single_res.status_code, 200)

        # 3. Bulk voter ID cards
        voter_bulk_url = f"/v1/elections/{self.election_1.id}/voters/id_cards_bulk/"
        voter_bulk_res = unauthenticated_client.get(voter_bulk_url)
        self.assertEqual(voter_bulk_res.status_code, 200)
        self.assertIn("CIVIL-001", voter_bulk_res.content.decode('utf-8'))

        # 4. Individual voter ID card
        voter_single_url = f"/v1/elections/{self.election_1.id}/voters/{self.roll_1a.id}/id_card/"
        voter_single_res = unauthenticated_client.get(voter_single_url)
        self.assertEqual(voter_single_res.status_code, 200)

    # --------------------------------------------------------------------------
    # Task 14: Voter Roll Election Scoping Tests
    # --------------------------------------------------------------------------
    def test_voter_can_only_see_enrolled_elections(self):
        """
        Voter A is only enrolled in Election 1.
        GET /v1/elections/ must ONLY return Election 1, never Election 2.
        """
        self.client.force_authenticate(user=self.voter_a)
        response = self.client.get("/v1/elections/")
        self.assertEqual(response.status_code, 200)
        election_ids = [e['id'] for e in response.data.get('results', response.data)]
        self.assertIn(str(self.election_1.id), election_ids)
        self.assertNotIn(str(self.election_2.id), election_ids)

    def test_voter_cannot_access_or_vote_in_unenrolled_election(self):
        """
        Voter A attempts to access ballot and session for Election 2.
        Must be rejected with not_eligible=True or 403 Forbidden.
        """
        self.client.force_authenticate(user=self.voter_a)
        
        # Ballot access check
        ballot_res = self.client.get(f"/v1/elections/{self.election_2.id}/voting/ballot/")
        self.assertEqual(ballot_res.status_code, 200)
        self.assertTrue(ballot_res.data.get('not_eligible'))

        # Voting session start check
        session_res = self.client.post(f"/v1/elections/{self.election_2.id}/voting/session/")
        self.assertEqual(session_res.status_code, 403)
        self.assertIn("not eligible", session_res.data.get('error', ''))

    def test_user_profile_returns_enrolled_elections(self):
        """
        GET /v1/auth/me/ should return enrolled_elections strictly for that voter.
        """
        self.client.force_authenticate(user=self.voter_a)
        response = self.client.get("/v1/auth/me/")
        self.assertEqual(response.status_code, 200)
        enrolled = response.data.get('enrolled_elections', [])
        self.assertEqual(len(enrolled), 1)
        self.assertEqual(enrolled[0]['election_id'], str(self.election_1.id))
        self.assertEqual(enrolled[0]['voter_id'], "CIVIL-001")
        self.assertFalse(enrolled[0]['has_voted'])
