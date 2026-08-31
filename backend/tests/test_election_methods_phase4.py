"""
Tests for Phase 4: Final Integration, Audit Exports & Multi-Method Verification
(doc: Election-Methods.pdf)
"""
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from rest_framework import status
import json

from apps.organizations.models import Organization, OrgStatus
from apps.users.models import User, UserRole
from apps.elections.models import Election, ElectionMethod, OnlineVotingType, Position, VotingMethod
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote


class TestElectionMethodsPhase4(TestCase):
    def setUp(self):
        self.client = APIClient()

        # 1. Organization
        self.org = Organization.objects.create(
            name='Nepal Bar Association',
            slug='nba-org',
            org_type='association',
            status=OrgStatus.ACTIVE,
        )

        # 2. Admin User
        self.admin = User.objects.create_user(
            email='admin@nba.org.np',
            password='AdminPassword@123',
            role=UserRole.ORG_ADMIN,
            organization=self.org,
        )

        # 3. Active Venue Election
        self.election = Election.objects.create(
            organization=self.org,
            title='NBA Central Executive Council Election',
            state='voting_open',
            election_method=ElectionMethod.VENUE,
            venue_name='Supreme Court Bar Hall',
            venue_address='Ramshah Path, Kathmandu',
            is_secret_ballot=True,
        )

        # 4. Voter Roll with various verification channels
        self.voter_app = VoterRoll.objects.create(
            election=self.election,
            voter_id='NBA-001',
            first_name='Adv. Ramesh',
            last_name='Karki',
            email='ramesh@example.com',
            phone='+9779841111111',
            is_eligible=True,
            has_voted=True,
            voted_at=timezone.now(),
            verification_channel='mobile_app',
            verified_at=timezone.now(),
        )

        self.voter_web = VoterRoll.objects.create(
            election=self.election,
            voter_id='NBA-002',
            first_name='Adv. Sunita',
            last_name='Dahal',
            email='sunita@example.com',
            phone='+9779842222222',
            is_eligible=True,
            has_voted=True,
            voted_at=timezone.now(),
            verification_channel='web_email',
            verified_at=timezone.now(),
        )

        self.voter_venue = VoterRoll.objects.create(
            election=self.election,
            voter_id='NBA-003',
            first_name='Adv. Pradeep',
            last_name='Shrestha',
            email='pradeep@example.com',
            phone='+9779843333333',
            is_eligible=True,
            has_voted=True,
            voted_at=timezone.now(),
            verification_channel='venue_kiosk',
            verified_at=timezone.now(),
        )

        self.voter_pending = VoterRoll.objects.create(
            election=self.election,
            voter_id='NBA-004',
            first_name='Adv. Manoj',
            last_name='Thapa',
            email='manoj@example.com',
            phone='+9779844444444',
            is_eligible=True,
            has_voted=False,
            verification_channel='unverified',
        )

    def test_voter_roll_api_serializes_verification_channel(self):
        """VoterRoll list API exposes verification_channel and verified_at."""
        self.client.force_authenticate(user=self.admin)
        url = f'/v1/elections/{self.election.id}/voters/'
        res = self.client.get(url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        voters_data = res.data if isinstance(res.data, list) else res.data.get('results', [])
        channels = {v['voter_id']: v.get('verification_channel') for v in voters_data}
        self.assertEqual(channels.get('NBA-001'), 'mobile_app')
        self.assertEqual(channels.get('NBA-002'), 'web_email')
        self.assertEqual(channels.get('NBA-003'), 'venue_kiosk')
        self.assertEqual(channels.get('NBA-004'), 'unverified')

    def test_voter_roll_csv_export_includes_verification_columns(self):
        """VoterRoll CSV export contains Verification Channel and Timestamp columns."""
        self.client.force_authenticate(user=self.admin)
        url = f'/v1/elections/{self.election.id}/voters/export_csv/'
        res = self.client.get(url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('text/csv', res['Content-Type'])

        content = res.content.decode('utf-8')
        self.assertIn('Verification Channel', content)
        self.assertIn('Verified At', content)
        self.assertIn('Has Voted', content)
        self.assertIn('Verified via Mobile App', content)
        self.assertIn('Verified via Web / Email', content)
        self.assertIn('Verified at Venue Kiosk', content)

    def test_audit_export_includes_election_methods_and_channels(self):
        """Auditor export package contains method metadata and verification breakdown."""
        self.client.force_authenticate(user=self.admin)
        url = f'/v1/elections/{self.election.id}/audit/export/'
        res = self.client.get(url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)

        package = json.loads(res.content.decode('utf-8'))
        self.assertEqual(package['election']['election_method'], 'venue')
        self.assertEqual(package['election']['venue_name'], 'Supreme Court Bar Hall')

        # Check verification breakdown
        channels = package['participation']['verification_channels']
        self.assertEqual(channels['mobile_app'], 1)
        self.assertEqual(channels['web_email'], 1)
        self.assertEqual(channels['venue_kiosk'], 1)
        self.assertEqual(channels['unverified'], 1)

        # Integrity hash is valid
        self.assertIn('package_integrity_hash', package)
        self.assertEqual(len(package['package_integrity_hash']), 64)
