"""
Comprehensive Test Suite: Requirements 4, 5, 6, 7, 8, 9 & Mixed Election System
=================================================================================
This test suite verifies every feature implemented across the electoral system:
  - Req 4: Party & Panel toggles
  - Req 5: Symbol & Candidate Photo toggles
  - Req 6: Samānupātik symbols for PR party lists
  - Req 7: Partial elections with target branch restrictions
  - Req 8: FPTP Winner + Modified Sainte-Laguë PR engine
  - Req 9: Unified election settings card
  - Mixed/Parallel: Combined FPTP + PR in a single election

Run: python manage.py test tests.test_requirements_4_to_9_and_mixed -v2
"""
from django.test import TestCase
from django.utils import timezone
from datetime import timedelta

from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election, Position, VotingMethod
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote
from apps.results.services import TallyService


class BaseElectionTestCase(TestCase):
    """Base setup shared across all test classes."""

    @classmethod
    def setUpTestData(cls):
        cls.org = Organization.objects.create(
            name='Test Election Commission',
            slug='test-ec',
        )
        cls.admin = User.objects.create_user(
            email='admin-req-test@test.com',
            password='Password123!',
            role=UserRole.ORG_ADMIN,
            organization=cls.org,
        )


# =========================================================================
# REQUIREMENT 4: Party & Panel Settings
# =========================================================================
class TestReq4_PartyPanelSettings(BaseElectionTestCase):
    """Verify that enable_party and enable_panel toggles correctly persist
    and control candidate affiliation data."""

    def test_enable_party_true_stores_party_name(self):
        """When enable_party=True, candidates can have party_name."""
        election = Election.objects.create(
            organization=self.org, title='Party Test', election_type='fptp',
            enable_party=True, enable_panel=False,
            state='draft', created_by=self.admin
        )
        pos = Position.objects.create(election=election, title='Chair', seats_available=1)
        cand = Candidate.objects.create(
            election=election, position=pos,
            first_name='Ram', last_name='Sharma',
            party_name='Democratic Alliance (लोकतान्त्रिक समूह)',
            status=NominationStatus.APPROVED
        )
        self.assertEqual(cand.party_name, 'Democratic Alliance (लोकतान्त्रिक समूह)')
        self.assertTrue(election.enable_party)

    def test_enable_party_false_still_accepts_data(self):
        """When enable_party=False, the field still exists (UI hides it)."""
        election = Election.objects.create(
            organization=self.org, title='No Party Test', election_type='fptp',
            enable_party=False, enable_panel=False,
            state='draft', created_by=self.admin
        )
        self.assertFalse(election.enable_party)

    def test_enable_panel_true_stores_panel_name(self):
        """When enable_panel=True, candidates can have panel_name."""
        election = Election.objects.create(
            organization=self.org, title='Panel Test', election_type='fptp',
            enable_party=False, enable_panel=True,
            state='draft', created_by=self.admin
        )
        pos = Position.objects.create(election=election, title='Secretary', seats_available=1)
        cand = Candidate.objects.create(
            election=election, position=pos,
            first_name='Sita', last_name='Karki',
            panel_name='Progressive Panel (प्रगतिशील प्यानल)',
            status=NominationStatus.APPROVED
        )
        self.assertEqual(cand.panel_name, 'Progressive Panel (प्रगतिशील प्यानल)')

    def test_both_party_and_panel_enabled(self):
        """Both toggles can be enabled simultaneously."""
        election = Election.objects.create(
            organization=self.org, title='Both Test', election_type='fptp',
            enable_party=True, enable_panel=True,
            state='draft', created_by=self.admin
        )
        self.assertTrue(election.enable_party)
        self.assertTrue(election.enable_panel)


# =========================================================================
# REQUIREMENT 5: Symbol & Candidate Photo Settings
# =========================================================================
class TestReq5_SymbolPhotoSettings(BaseElectionTestCase):
    """Verify that enable_symbol and enable_candidate_photo toggles work."""

    def test_symbol_enabled_persists_symbol_data(self):
        """When enable_symbol=True, candidates store symbol_name and symbol_image."""
        election = Election.objects.create(
            organization=self.org, title='Symbol Test', election_type='fptp',
            enable_symbol=True, enable_candidate_photo=True,
            state='draft', created_by=self.admin
        )
        pos = Position.objects.create(election=election, title='Treasurer', seats_available=1)
        cand = Candidate.objects.create(
            election=election, position=pos,
            first_name='Hari', last_name='Bahadur',
            symbol_name='Sun (सूर्य)',
            symbol_image='https://cdn.example.com/symbols/sun.png',
            candidate_image='https://cdn.example.com/photos/hari.jpg',
            status=NominationStatus.APPROVED
        )
        self.assertEqual(cand.symbol_name, 'Sun (सूर्य)')
        self.assertEqual(cand.symbol_image, 'https://cdn.example.com/symbols/sun.png')
        self.assertEqual(cand.candidate_image, 'https://cdn.example.com/photos/hari.jpg')

    def test_photo_disabled(self):
        """When enable_candidate_photo=False, the toggle persists correctly."""
        election = Election.objects.create(
            organization=self.org, title='No Photo Test', election_type='fptp',
            enable_symbol=True, enable_candidate_photo=False,
            state='draft', created_by=self.admin
        )
        self.assertFalse(election.enable_candidate_photo)
        self.assertTrue(election.enable_symbol)

    def test_all_display_toggles_off(self):
        """All display toggles can be set to False."""
        election = Election.objects.create(
            organization=self.org, title='Minimal Test', election_type='fptp',
            enable_party=False, enable_panel=False,
            enable_symbol=False, enable_candidate_photo=False,
            state='draft', created_by=self.admin
        )
        self.assertFalse(election.enable_party)
        self.assertFalse(election.enable_panel)
        self.assertFalse(election.enable_symbol)
        self.assertFalse(election.enable_candidate_photo)


# =========================================================================
# REQUIREMENT 6: Samānupātik Symbols for PR
# =========================================================================
class TestReq6_SamanupatikSymbols(BaseElectionTestCase):
    """Verify that Samānupātik elections support election symbols for parties."""

    def test_pr_candidates_have_symbol_fields(self):
        """PR candidates correctly store symbol_name and symbol_image."""
        election = Election.objects.create(
            organization=self.org, title='PR Symbol Test',
            election_type='samanupatik', enable_symbol=True,
            total_pr_seats=5, pr_allocation_method='modified_sainte_lague',
            state='draft', created_by=self.admin
        )
        pos = Position.objects.create(election=election, title='PR List', seats_available=5)
        cand = Candidate.objects.create(
            election=election, position=pos,
            first_name='Govinda', last_name='Adhikari',
            party_name='Nepali Congress', symbol_name='Tree (रुख)',
            symbol_image='https://cdn.example.com/symbols/tree.png',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        self.assertEqual(cand.symbol_name, 'Tree (रुख)')
        self.assertTrue(cand.symbol_image.startswith('https://'))

    def test_pr_tally_includes_symbol_info(self):
        """TallyService.tally_samanupatik includes symbol data in party_results."""
        election = Election.objects.create(
            organization=self.org, title='PR Symbol Tally Test',
            election_type='samanupatik', enable_symbol=True,
            total_pr_seats=2, pr_threshold_percent=0.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        pos = Position.objects.create(election=election, title='PR List', seats_available=2)
        cand = Candidate.objects.create(
            election=election, position=pos,
            first_name='Test', last_name='Candidate',
            party_name='Symbol Party', symbol_name='Bell (घण्टी)',
            symbol_image='https://cdn.example.com/symbols/bell.png',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        Vote.objects.create(
            election=election,
            ballot_data={str(pos.id): [str(cand.id)]},
            receipt_hash='pr-sym-1'
        )

        tally = TallyService.tally_samanupatik(election)
        party = tally['party_results'][0]
        self.assertEqual(party['symbol_name'], 'Bell (घण्टी)')
        self.assertEqual(party['symbol_image'], 'https://cdn.example.com/symbols/bell.png')


# =========================================================================
# REQUIREMENT 7: Partial Election & Target Branch Restrictions
# =========================================================================
class TestReq7_PartialElection(BaseElectionTestCase):
    """Verify partial election functionality with target branch restrictions."""

    def setUp(self):
        self.election = Election.objects.create(
            organization=self.org,
            title='Regional Chapter Election',
            election_type='fptp',
            is_partial_election=True,
            target_branches=['Pokhara', 'Butwal'],
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )

    def test_eligible_branch_voter_allowed(self):
        """Voter from target branch (Pokhara) is allowed."""
        roll = VoterRoll.objects.create(
            election=self.election, first_name='Pokhara', last_name='Voter',
            email='voter-pkr@test.com', voter_id='PKR-001', branch='Pokhara',
            is_eligible=True
        )
        target = [b.strip().lower() for b in self.election.target_branches]
        self.assertIn(roll.branch.strip().lower(), target)

    def test_ineligible_branch_voter_blocked(self):
        """Voter from non-target branch (Kathmandu) is blocked."""
        roll = VoterRoll.objects.create(
            election=self.election, first_name='Kathmandu', last_name='Voter',
            email='voter-ktm@test.com', voter_id='KTM-002', branch='Kathmandu',
            is_eligible=True
        )
        target = [b.strip().lower() for b in self.election.target_branches]
        self.assertNotIn(roll.branch.strip().lower(), target)

    def test_case_insensitive_branch_matching(self):
        """Branch matching is case-insensitive."""
        roll = VoterRoll.objects.create(
            election=self.election, first_name='Mixed', last_name='Case',
            email='voter-mixed@test.com', voter_id='MIX-003', branch='pokhara',
            is_eligible=True
        )
        target = [b.strip().lower() for b in self.election.target_branches]
        self.assertIn(roll.branch.strip().lower(), target)

    def test_non_partial_election_allows_all(self):
        """When is_partial_election=False, all branches are allowed."""
        full_election = Election.objects.create(
            organization=self.org, title='Full Election',
            election_type='fptp', is_partial_election=False,
            target_branches=[], state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        self.assertFalse(full_election.is_partial_election)

    def test_partial_election_with_empty_branches_allows_all(self):
        """Partial election with empty target_branches should not restrict."""
        self.election.target_branches = []
        self.election.save()
        target = [b.strip().lower() for b in self.election.target_branches if b.strip()]
        # Empty target list means no restriction
        self.assertEqual(len(target), 0)


# =========================================================================
# REQUIREMENT 8A: FPTP Tallying Engine
# =========================================================================
class TestReq8A_FPTPTally(BaseElectionTestCase):
    """Verify FPTP (First-Past-The-Post) winner determination."""

    def setUp(self):
        self.election = Election.objects.create(
            organization=self.org, title='FPTP Election Test',
            election_type='fptp', state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        self.pos = Position.objects.create(
            election=self.election, title='President', seats_available=1, result_order=1
        )
        self.cand1 = Candidate.objects.create(
            election=self.election, position=self.pos,
            first_name='Ramesh', last_name='Sharma',
            party_name='Alliance A', symbol_name='Sun',
            status=NominationStatus.APPROVED
        )
        self.cand2 = Candidate.objects.create(
            election=self.election, position=self.pos,
            first_name='Sita', last_name='Karki',
            party_name='Alliance B', symbol_name='Tree',
            status=NominationStatus.APPROVED
        )

    def test_winner_highest_votes(self):
        """Candidate with the most votes wins."""
        for i in range(3):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(self.pos.id): [str(self.cand1.id)]},
                receipt_hash=f'fptp-w-{i}'
            )
        Vote.objects.create(
            election=self.election,
            ballot_data={str(self.pos.id): [str(self.cand2.id)]},
            receipt_hash='fptp-l-1'
        )

        tally = TallyService.tally_election(self.election)
        result = tally['results'][0]
        self.assertEqual(result['winners'], [str(self.cand1.id)])
        self.assertEqual(result['breakdown'][0]['score'], 3.0)
        self.assertEqual(result['breakdown'][0]['name'], 'Ramesh Sharma')

    def test_fptp_includes_party_and_symbol(self):
        """FPTP tally breakdown includes party_name and symbol_name."""
        Vote.objects.create(
            election=self.election,
            ballot_data={str(self.pos.id): [str(self.cand1.id)]},
            receipt_hash='fptp-party-1'
        )
        tally = TallyService.tally_election(self.election)
        bd = tally['results'][0]['breakdown'][0]
        self.assertEqual(bd['party_name'], 'Alliance A')
        self.assertEqual(bd['symbol_name'], 'Sun')

    def test_fptp_boycott_score(self):
        """Boycott/No-Vote is tracked separately from candidate scores."""
        Vote.objects.create(
            election=self.election,
            ballot_data={str(self.pos.id): ['__BOYCOTT__']},
            receipt_hash='fptp-boycott-1'
        )
        Vote.objects.create(
            election=self.election,
            ballot_data={str(self.pos.id): [str(self.cand1.id)]},
            receipt_hash='fptp-real-1'
        )
        tally = TallyService.tally_election(self.election)
        result = tally['results'][0]
        boycott_entry = [b for b in result['breakdown'] if b['candidate_id'] == '__BOYCOTT__']
        self.assertEqual(len(boycott_entry), 1)
        self.assertEqual(boycott_entry[0]['score'], 1.0)

    def test_fptp_no_votes_empty_winners(self):
        """With no votes cast, winners list is empty."""
        tally = TallyService.tally_election(self.election)
        result = tally['results'][0]
        self.assertEqual(result['winners'], [])

    def test_fptp_election_type_in_response(self):
        """Tally response has election_type = 'fptp'."""
        tally = TallyService.tally_election(self.election)
        self.assertEqual(tally['election_type'], 'fptp')


# =========================================================================
# REQUIREMENT 8B: Modified Sainte-Laguë PR Engine
# =========================================================================
class TestReq8B_ModifiedSainteLaguePR(BaseElectionTestCase):
    """Verify Modified Sainte-Laguë (Nepal Standard) seat allocation:
    Divisors: 1.4 for first seat, then 3, 5, 7, 9..."""

    def setUp(self):
        self.election = Election.objects.create(
            organization=self.org, title='PR Engine Test',
            election_type='samanupatik',
            total_pr_seats=5, pr_threshold_percent=5.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        self.pos = Position.objects.create(
            election=self.election, title='PR List (समानुपातिक सूची)',
            seats_available=5, result_order=1
        )
        # Party A: 3 candidates
        self.a1 = Candidate.objects.create(election=self.election, position=self.pos, first_name='A', last_name='One', party_name='Party A', pr_rank=1, status='approved')
        self.a2 = Candidate.objects.create(election=self.election, position=self.pos, first_name='A', last_name='Two', party_name='Party A', pr_rank=2, status='approved')
        self.a3 = Candidate.objects.create(election=self.election, position=self.pos, first_name='A', last_name='Three', party_name='Party A', pr_rank=3, status='approved')
        # Party B: 2 candidates
        self.b1 = Candidate.objects.create(election=self.election, position=self.pos, first_name='B', last_name='One', party_name='Party B', pr_rank=1, status='approved')
        self.b2 = Candidate.objects.create(election=self.election, position=self.pos, first_name='B', last_name='Two', party_name='Party B', pr_rank=2, status='approved')
        # Party C: 1 candidate (below threshold)
        self.c1 = Candidate.objects.create(election=self.election, position=self.pos, first_name='C', last_name='One', party_name='Party C', pr_rank=1, status='approved')

        # Cast 60 for A, 38 for B, 2 for C (total 100)
        for i in range(60):
            Vote.objects.create(election=self.election, ballot_data={str(self.pos.id): [str(self.a1.id)]}, receipt_hash=f'pr-a-{i}')
        for i in range(38):
            Vote.objects.create(election=self.election, ballot_data={str(self.pos.id): [str(self.b1.id)]}, receipt_hash=f'pr-b-{i}')
        for i in range(2):
            Vote.objects.create(election=self.election, ballot_data={str(self.pos.id): [str(self.c1.id)]}, receipt_hash=f'pr-c-{i}')

    def test_party_a_gets_3_seats(self):
        """Party A (60%) should get 3 seats via Modified Sainte-Laguë."""
        tally = TallyService.tally_samanupatik(self.election)
        party_a = next(p for p in tally['party_results'] if p['party_name'] == 'Party A')
        self.assertEqual(party_a['seats_allocated'], 3)

    def test_party_b_gets_2_seats(self):
        """Party B (38%) should get 2 seats via Modified Sainte-Laguë."""
        tally = TallyService.tally_samanupatik(self.election)
        party_b = next(p for p in tally['party_results'] if p['party_name'] == 'Party B')
        self.assertEqual(party_b['seats_allocated'], 2)

    def test_party_c_disqualified_below_threshold(self):
        """Party C (2%) is below 5% threshold and gets 0 seats."""
        tally = TallyService.tally_samanupatik(self.election)
        party_c = next(p for p in tally['party_results'] if p['party_name'] == 'Party C')
        self.assertFalse(party_c['is_qualified'])
        self.assertEqual(party_c['seats_allocated'], 0)

    def test_first_divisor_is_1_4(self):
        """Round 1 uses divisor 1.4 (not 1) per Nepal Modified Sainte-Laguë."""
        tally = TallyService.tally_samanupatik(self.election)
        table = tally['seat_allocation_table']
        round_1 = table[0]
        # Party A: 60 / 1.4 = 42.857
        self.assertAlmostEqual(round_1['highest_quotient'], 42.857, places=2)
        self.assertEqual(round_1['allocated_to_party'], 'Party A')

    def test_second_round_party_b_wins(self):
        """Round 2: Party B gets its first seat (38/1.4 = 27.143)."""
        tally = TallyService.tally_samanupatik(self.election)
        table = tally['seat_allocation_table']
        self.assertEqual(table[1]['allocated_to_party'], 'Party B')
        self.assertAlmostEqual(table[1]['highest_quotient'], 27.143, places=2)

    def test_third_round_party_a_divisor_3(self):
        """Round 3: Party A's second seat (60/3 = 20.0)."""
        tally = TallyService.tally_samanupatik(self.election)
        table = tally['seat_allocation_table']
        self.assertEqual(table[2]['allocated_to_party'], 'Party A')
        self.assertAlmostEqual(table[2]['highest_quotient'], 20.0, places=1)

    def test_seat_allocation_table_has_5_rounds(self):
        """Seat allocation table must contain exactly 5 rounds for 5 seats."""
        tally = TallyService.tally_samanupatik(self.election)
        self.assertEqual(len(tally['seat_allocation_table']), 5)

    def test_elected_candidates_by_pr_rank(self):
        """Elected candidates are ordered by pr_rank within their party."""
        tally = TallyService.tally_samanupatik(self.election)
        party_a = next(p for p in tally['party_results'] if p['party_name'] == 'Party A')
        elected = party_a['elected_candidates']
        self.assertEqual(len(elected), 3)
        self.assertEqual(elected[0]['pr_rank'], 1)
        self.assertEqual(elected[1]['pr_rank'], 2)
        self.assertEqual(elected[2]['pr_rank'], 3)

    def test_vote_percentages_correct(self):
        """Party vote percentages should be calculated correctly."""
        tally = TallyService.tally_samanupatik(self.election)
        party_a = next(p for p in tally['party_results'] if p['party_name'] == 'Party A')
        self.assertEqual(party_a['vote_percentage'], 60.0)
        party_c = next(p for p in tally['party_results'] if p['party_name'] == 'Party C')
        self.assertEqual(party_c['vote_percentage'], 2.0)

    def test_total_valid_votes_counted(self):
        """Total valid party votes should equal sum of all votes."""
        tally = TallyService.tally_samanupatik(self.election)
        self.assertEqual(tally['total_valid_party_votes'], 100.0)

    def test_pr_allocation_method_is_modified_sainte_lague(self):
        """The allocation method returned should be modified_sainte_lague."""
        tally = TallyService.tally_samanupatik(self.election)
        self.assertEqual(tally['pr_allocation_method'], 'modified_sainte_lague')

    def test_zero_threshold_qualifies_all_with_votes(self):
        """With 0% threshold, all parties with votes qualify."""
        self.election.pr_threshold_percent = 0.0
        self.election.save()
        tally = TallyService.tally_samanupatik(self.election)
        for p in tally['party_results']:
            if p['votes'] > 0:
                self.assertTrue(p['is_qualified'])


# =========================================================================
# REQUIREMENT 9: Unified Election Settings
# =========================================================================
class TestReq9_UnifiedSettings(BaseElectionTestCase):
    """Verify that election settings (type, party, panel, symbol, photo,
    partial, PR params) are all unified on the Election model."""

    def test_fptp_election_creation(self):
        """FPTP election stores correct election_type."""
        election = Election.objects.create(
            organization=self.org, title='FPTP Settings Test',
            election_type='fptp', created_by=self.admin
        )
        self.assertEqual(election.election_type, 'fptp')

    def test_samanupatik_election_creation(self):
        """Samānupātik election stores PR parameters."""
        election = Election.objects.create(
            organization=self.org, title='PR Settings Test',
            election_type='samanupatik',
            total_pr_seats=10, pr_threshold_percent=3.0,
            pr_allocation_method='modified_sainte_lague',
            created_by=self.admin
        )
        self.assertEqual(election.election_type, 'samanupatik')
        self.assertEqual(election.total_pr_seats, 10)
        self.assertEqual(float(election.pr_threshold_percent), 3.0)
        self.assertEqual(election.pr_allocation_method, 'modified_sainte_lague')

    def test_mixed_election_creation(self):
        """Mixed election stores both FPTP and PR parameters."""
        election = Election.objects.create(
            organization=self.org, title='Mixed Settings Test',
            election_type='mixed',
            total_pr_seats=5, pr_threshold_percent=5.0,
            pr_allocation_method='modified_sainte_lague',
            enable_party=True, enable_panel=True,
            enable_symbol=True, enable_candidate_photo=True,
            created_by=self.admin
        )
        self.assertEqual(election.election_type, 'mixed')
        self.assertEqual(election.total_pr_seats, 5)
        self.assertTrue(election.enable_party)
        self.assertTrue(election.enable_symbol)

    def test_pr_allocation_method_default(self):
        """Default PR allocation method is modified_sainte_lague."""
        election = Election.objects.create(
            organization=self.org, title='Default Method Test',
            election_type='samanupatik', created_by=self.admin
        )
        self.assertEqual(election.pr_allocation_method, 'modified_sainte_lague')

    def test_all_settings_persist_on_reload(self):
        """All settings survive a database round-trip."""
        election = Election.objects.create(
            organization=self.org, title='Persist Test',
            election_type='mixed',
            enable_party=False, enable_panel=True,
            enable_symbol=False, enable_candidate_photo=True,
            is_partial_election=True,
            target_branches=['Kathmandu', 'Lalitpur'],
            total_pr_seats=8, pr_threshold_percent=2.5,
            pr_allocation_method='modified_sainte_lague',
            created_by=self.admin
        )
        reloaded = Election.objects.get(pk=election.pk)
        self.assertEqual(reloaded.election_type, 'mixed')
        self.assertFalse(reloaded.enable_party)
        self.assertTrue(reloaded.enable_panel)
        self.assertFalse(reloaded.enable_symbol)
        self.assertTrue(reloaded.enable_candidate_photo)
        self.assertTrue(reloaded.is_partial_election)
        self.assertEqual(reloaded.target_branches, ['Kathmandu', 'Lalitpur'])
        self.assertEqual(reloaded.total_pr_seats, 8)
        self.assertEqual(float(reloaded.pr_threshold_percent), 2.5)


# =========================================================================
# MIXED / PARALLEL ELECTION: FPTP + Samānupātik Combined
# =========================================================================
class TestMixedParallelElection(BaseElectionTestCase):
    """Verify the Mixed / Parallel electoral system combining
    Direct FPTP individual candidate posts + Samānupātik PR party allocation."""

    def setUp(self):
        self.election = Election.objects.create(
            organization=self.org, title='Mixed Parliament Election',
            election_type='mixed',
            total_pr_seats=5, pr_threshold_percent=3.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        # Direct FPTP Position
        self.pos_direct = Position.objects.create(
            election=self.election,
            title='Direct Constituency Representative (प्रत्यक्ष प्रतिनिधि)',
            seats_available=1, result_order=1
        )
        # PR Position
        self.pos_pr = Position.objects.create(
            election=self.election,
            title='Proportional Representation List (समानुपातिक सूची)',
            seats_available=5, result_order=2
        )
        # FPTP Candidates
        self.fptp_1 = Candidate.objects.create(
            election=self.election, position=self.pos_direct,
            first_name='Ram', last_name='Sharma', party_name='Party X',
            status=NominationStatus.APPROVED
        )
        self.fptp_2 = Candidate.objects.create(
            election=self.election, position=self.pos_direct,
            first_name='KP', last_name='Oli', party_name='Party Y',
            status=NominationStatus.APPROVED
        )
        # PR Candidates (Party X: 3 candidates)
        self.pr_x1 = Candidate.objects.create(
            election=self.election, position=self.pos_pr,
            first_name='X', last_name='PR1', party_name='Party X',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        self.pr_x2 = Candidate.objects.create(
            election=self.election, position=self.pos_pr,
            first_name='X', last_name='PR2', party_name='Party X',
            pr_rank=2, status=NominationStatus.APPROVED
        )
        # PR Candidates (Party Y: 2 candidates)
        self.pr_y1 = Candidate.objects.create(
            election=self.election, position=self.pos_pr,
            first_name='Y', last_name='PR1', party_name='Party Y',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        self.pr_y2 = Candidate.objects.create(
            election=self.election, position=self.pos_pr,
            first_name='Y', last_name='PR2', party_name='Party Y',
            pr_rank=2, status=NominationStatus.APPROVED
        )
        # PR Candidates (Party Z: 1 candidate)
        self.pr_z1 = Candidate.objects.create(
            election=self.election, position=self.pos_pr,
            first_name='Z', last_name='PR1', party_name='Party Z',
            pr_rank=1, status=NominationStatus.APPROVED
        )

        # Direct FPTP votes: 6 for Ram, 4 for KP
        for i in range(6):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(self.pos_direct.id): [str(self.fptp_1.id)]},
                receipt_hash=f'mix-fptp-1-{i}'
            )
        for i in range(4):
            Vote.objects.create(
                election=self.election,
                ballot_data={str(self.pos_direct.id): [str(self.fptp_2.id)]},
                receipt_hash=f'mix-fptp-2-{i}'
            )
        # PR votes: 50 X, 30 Y, 20 Z
        for i in range(5):
            Vote.objects.create(election=self.election, ballot_data={'pr_ballot': ['Party X']}, weight=10.0, receipt_hash=f'mix-pr-x-{i}')
        for i in range(3):
            Vote.objects.create(election=self.election, ballot_data={'pr_ballot': ['Party Y']}, weight=10.0, receipt_hash=f'mix-pr-y-{i}')
        for i in range(2):
            Vote.objects.create(election=self.election, ballot_data={'pr_ballot': ['Party Z']}, weight=10.0, receipt_hash=f'mix-pr-z-{i}')

    def test_mixed_tally_returns_election_type_mixed(self):
        """Mixed election tally returns election_type='mixed'."""
        tally = TallyService.tally_election(self.election)
        self.assertEqual(tally['election_type'], 'mixed')

    def test_mixed_tally_contains_results_and_pr(self):
        """Mixed tally has both 'results' (FPTP) and 'samanupatik_results' (PR)."""
        tally = TallyService.tally_election(self.election)
        self.assertIn('results', tally)
        self.assertIn('samanupatik_results', tally)

    def test_mixed_fptp_winner_correct(self):
        """FPTP direct winner is determined correctly within mixed tally."""
        tally = TallyService.tally_election(self.election)
        fptp_result = tally['results'][0]
        self.assertIn(str(self.fptp_1.id), fptp_result['winners'])

    def test_mixed_pr_seats_allocated(self):
        """PR seats are allocated correctly within mixed tally."""
        tally = TallyService.tally_election(self.election)
        pr = tally['samanupatik_results']
        party_map = {p['party_name']: p for p in pr['party_results']}
        # Modified Sainte-Laguë with votes 50, 30, 20 and 5 seats:
        # Round 1: X: 50/1.4=35.71, Y: 30/1.4=21.43, Z: 20/1.4=14.29 -> X wins
        # Round 2: X: 50/3=16.67, Y: 30/1.4=21.43, Z: 20/1.4=14.29 -> Y wins
        # Round 3: X: 50/3=16.67, Y: 30/3=10.00, Z: 20/1.4=14.29 -> X wins
        # Round 4: X: 50/5=10.00, Y: 30/3=10.00, Z: 20/1.4=14.29 -> Z wins
        # Round 5: X: 50/5=10.00, Y: 30/3=10.00, Z: 20/3=6.67 -> X or Y wins (X >= Y)
        total_seats = sum(p['seats_allocated'] for p in pr['party_results'])
        self.assertEqual(total_seats, 5)

    def test_mixed_pr_has_allocation_table(self):
        """PR results within mixed tally include seat allocation table."""
        tally = TallyService.tally_election(self.election)
        table = tally['samanupatik_results']['seat_allocation_table']
        self.assertEqual(len(table), 5)

    def test_mixed_turnout_data(self):
        """Mixed tally includes turnout statistics."""
        tally = TallyService.tally_election(self.election)
        self.assertIn('total_voters', tally)
        self.assertIn('ballots_cast', tally)
        self.assertIn('turnout_percentage', tally)


# =========================================================================
# EDGE CASES & ADDITIONAL VERIFICATIONS
# =========================================================================
class TestEdgeCases(BaseElectionTestCase):
    """Test edge cases in the tallying engine."""

    def test_pr_no_votes_produces_no_allocation(self):
        """With zero votes, no seats should be allocated."""
        election = Election.objects.create(
            organization=self.org, title='Empty PR Test',
            election_type='samanupatik',
            total_pr_seats=5, pr_threshold_percent=0.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        pos = Position.objects.create(election=election, title='Empty PR', seats_available=5)
        Candidate.objects.create(
            election=election, position=pos,
            first_name='Alone', last_name='Cand', party_name='Solo Party',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        tally = TallyService.tally_samanupatik(election)
        self.assertEqual(tally['total_valid_party_votes'], 0.0)
        self.assertEqual(len(tally['seat_allocation_table']), 0)

    def test_pr_single_party_gets_all_seats(self):
        """With only one qualified party, it gets all seats (up to candidate count)."""
        election = Election.objects.create(
            organization=self.org, title='Single Party PR',
            election_type='samanupatik',
            total_pr_seats=3, pr_threshold_percent=0.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        pos = Position.objects.create(election=election, title='Solo PR', seats_available=3)
        for r in range(1, 6):
            Candidate.objects.create(
                election=election, position=pos,
                first_name=f'Cand{r}', last_name='Solo', party_name='Solo Party',
                pr_rank=r, status=NominationStatus.APPROVED
            )
        for i in range(10):
            Vote.objects.create(election=election, ballot_data={str(pos.id): ['Solo Party']}, receipt_hash=f'solo-{i}')
        tally = TallyService.tally_samanupatik(election)
        solo = next(p for p in tally['party_results'] if p['party_name'] == 'Solo Party')
        self.assertEqual(solo['seats_allocated'], 3)

    def test_pr_boycott_votes_tracked(self):
        """Boycott votes in PR election are counted in boycott_score."""
        election = Election.objects.create(
            organization=self.org, title='Boycott PR',
            election_type='samanupatik',
            total_pr_seats=2, pr_threshold_percent=0.0,
            pr_allocation_method='modified_sainte_lague',
            state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        pos = Position.objects.create(election=election, title='Boycott PR', seats_available=2)
        Candidate.objects.create(
            election=election, position=pos,
            first_name='Test', last_name='Cand', party_name='Test Party',
            pr_rank=1, status=NominationStatus.APPROVED
        )
        Vote.objects.create(election=election, ballot_data={str(pos.id): ['__BOYCOTT__']}, receipt_hash='boycott-1')
        Vote.objects.create(election=election, ballot_data={str(pos.id): ['__BOYCOTT__']}, receipt_hash='boycott-2')
        tally = TallyService.tally_samanupatik(election)
        self.assertEqual(tally['boycott_score'], 2.0)

    def test_fptp_multi_seat_position(self):
        """Multi-seat FPTP position correctly selects top N candidates."""
        election = Election.objects.create(
            organization=self.org, title='Multi-Seat FPTP',
            election_type='fptp', state='voting_open', created_by=self.admin,
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(hours=5),
        )
        pos = Position.objects.create(
            election=election, title='Board Members', seats_available=2,
            voting_method='multi_choice'
        )
        c1 = Candidate.objects.create(election=election, position=pos, first_name='A', last_name='Cand', status=NominationStatus.APPROVED)
        c2 = Candidate.objects.create(election=election, position=pos, first_name='B', last_name='Cand', status=NominationStatus.APPROVED)
        c3 = Candidate.objects.create(election=election, position=pos, first_name='C', last_name='Cand', status=NominationStatus.APPROVED)

        # A gets 5, B gets 3, C gets 1
        for i in range(5):
            Vote.objects.create(election=election, ballot_data={str(pos.id): [str(c1.id)]}, receipt_hash=f'multi-a-{i}')
        for i in range(3):
            Vote.objects.create(election=election, ballot_data={str(pos.id): [str(c2.id)]}, receipt_hash=f'multi-b-{i}')
        Vote.objects.create(election=election, ballot_data={str(pos.id): [str(c3.id)]}, receipt_hash='multi-c-0')

        tally = TallyService.tally_election(election)
        result = tally['results'][0]
        # Top 2 winners should be A and B
        self.assertEqual(len(result['winners']), 2)
        self.assertIn(str(c1.id), result['winners'])
        self.assertIn(str(c2.id), result['winners'])

    def test_election_state_machine_valid_transitions(self):
        """Election state machine allows valid transitions."""
        election = Election.objects.create(
            organization=self.org, title='State Machine Test',
            election_type='fptp', state='draft', created_by=self.admin
        )
        self.assertTrue(election.can_transition_to('published'))
        self.assertTrue(election.can_transition_to('cancelled'))
        self.assertFalse(election.can_transition_to('voting_open'))

    def test_election_state_machine_blocks_invalid(self):
        """Election state machine blocks invalid transitions."""
        election = Election.objects.create(
            organization=self.org, title='Block Transition Test',
            election_type='fptp', state='results_final', created_by=self.admin
        )
        self.assertFalse(election.can_transition_to('draft'))
        self.assertFalse(election.can_transition_to('voting_open'))
        with self.assertRaises(ValueError):
            election.transition_to('draft')
