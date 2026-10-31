"""Election schedule milestones must follow one another (create and edit)."""
from datetime import timedelta
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election


class TestElectionScheduleOrder(TestCase):

    def setUp(self):
        self.client = APIClient()
        self.org = Organization.objects.create(name='Org', slug='org')
        self.admin = User.objects.create_user(email='admin@org.test', password='Admin@12345',
                                              organization=self.org, role=UserRole.ORG_ADMIN)
        self.client.force_authenticate(user=self.admin)
        self.t0 = timezone.now() + timedelta(days=1)

    def at(self, hours):
        return (self.t0 + timedelta(hours=hours)).isoformat()

    def test_final_candidate_list_before_claims_is_rejected(self):
        # The NESOG case: final list 1 minute before the candidacy claims deadline.
        r = self.client.post('/v1/elections/', {
            'title': 'E',
            'nomination_open_at': self.at(0), 'nomination_close_at': self.at(1),
            'candidacy_claim_date': self.at(3), 'candidacy_final_date': self.at(2),
        }, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn('candidacy_final_date', str(r.data))

    def test_valid_schedule_is_accepted(self):
        r = self.client.post('/v1/elections/', {
            'title': 'E',
            'first_voter_list_date': self.at(0), 'voter_list_claim_date': self.at(1), 'final_voter_list_date': self.at(2),
            'nomination_open_at': self.at(3), 'nomination_close_at': self.at(4),
            'candidacy_claim_date': self.at(5), 'candidacy_final_date': self.at(6),
            'withdrawal_deadline': self.at(6), 'campaign_silent_from': self.at(7),
            'voting_start_at': self.at(8), 'voting_end_at': self.at(9), 'result_contest_deadline': self.at(10),
        }, format='json')
        self.assertEqual(r.status_code, 201, r.data)

    def test_edit_checks_against_saved_dates(self):
        e = Election.objects.create(organization=self.org, title='E',
                                    voting_start_at=self.t0 + timedelta(hours=8),
                                    voting_end_at=self.t0 + timedelta(hours=9))
        # Moving only the final voter list after the saved voting start is rejected
        r = self.client.patch(f'/v1/elections/{e.id}/', {'final_voter_list_date': self.at(10)}, format='json')
        self.assertEqual(r.status_code, 400)
        self.assertIn('voting_start_at', str(r.data))
        r = self.client.patch(f'/v1/elections/{e.id}/', {'final_voter_list_date': self.at(7)}, format='json')
        self.assertEqual(r.status_code, 200, r.data)

    def test_unrelated_edit_of_legacy_out_of_order_election_is_allowed(self):
        e = Election.objects.create(organization=self.org, title='Legacy',
                                    candidacy_claim_date=self.t0 + timedelta(hours=3),
                                    candidacy_final_date=self.t0 + timedelta(hours=2))
        r = self.client.patch(f'/v1/elections/{e.id}/', {'title': 'Legacy renamed'}, format='json')
        self.assertEqual(r.status_code, 200, r.data)
        r = self.client.patch(f'/v1/elections/{e.id}/', {'candidacy_final_date': self.at(1)}, format='json')
        self.assertEqual(r.status_code, 400)
