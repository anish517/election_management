"""
Nomination fees: proof is required whenever a fee applies (position, election
or organization default), approval needs a verified payment, and payers can't
edit payment records or nominations directly.
"""
from decimal import Decimal
from unittest.mock import patch
from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from apps.organizations.models import Organization
from apps.users.models import User, UserRole
from apps.elections.models import Election, ElectionState, Position
from apps.voting.models import VoterRoll
from apps.candidates.models import Candidate
from apps.billing.models import Payment


class TestNominationPayments(TestCase):

    def setUp(self):
        # Approval queues a Celery notification; no broker in tests.
        patcher = patch('apps.notifications.tasks.send_candidate_approved_notification.delay')
        patcher.start()
        self.addCleanup(patcher.stop)
        self.client = APIClient()
        self.org = Organization.objects.create(
            name='Org', slug='org', payment_settings={'is_payment_enabled': True},
        )
        # Fee set on the election only; the position has none.
        self.election = Election.objects.create(
            organization=self.org, title='E', state=ElectionState.NOMINATION_OPEN,
            nominee_charge=Decimal('500.00'),
        )
        self.pos = Position.objects.create(election=self.election, title='President', seats_available=1)
        self.voter = User.objects.create_user(email='me@org.test', password='Voter@12345', organization=self.org,
                                              role=UserRole.VOTER, phone='9800000001')
        VoterRoll.objects.create(election=self.election, voter_id='V1', first_name='Me', last_name='Voter',
                                 email='me@org.test', phone='9800000001')
        self.admin = User.objects.create_user(email='admin@org.test', password='Admin@12345', organization=self.org,
                                              role=UserRole.ORG_ADMIN)
        self.url = f'/v1/elections/{self.election.id}/candidates/'

    def nominate(self, **extra):
        self.client.force_authenticate(user=self.voter)
        return self.client.post(self.url, {'position': str(self.pos.id), 'manifesto': 'm', **extra}, format='json')

    def test_election_level_fee_requires_proof(self):
        r = self.nominate()
        self.assertEqual(r.status_code, status.HTTP_400_BAD_REQUEST, r.data)
        self.assertFalse(Candidate.objects.exists())

    def test_with_proof_is_pending_and_records_server_fee(self):
        r = self.nominate(transaction_reference='TXN-1', payment_status='paid')
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)
        cand = Candidate.objects.get()
        self.assertEqual(cand.payment_status, 'pending_verification')
        self.assertEqual(Payment.objects.get().amount, Decimal('500.00'))

    def test_free_when_payments_off(self):
        self.org.payment_settings = {'is_payment_enabled': False}
        self.org.save(update_fields=['payment_settings'])
        r = self.nominate()
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)
        self.assertEqual(Candidate.objects.get().payment_status, 'waived')

    def test_approval_requires_verified_payment(self):
        self.nominate(transaction_reference='TXN-1')
        cand = Candidate.objects.get()
        payment = Payment.objects.get()
        self.client.force_authenticate(user=self.admin)
        approve = f'{self.url}{cand.id}/approve/'
        self.assertEqual(self.client.post(approve, {}, format='json').status_code, 400)
        self.assertEqual(self.client.post(f'/v1/payments/{payment.id}/verify/', {}, format='json').status_code, 200)
        self.assertEqual(self.client.post(approve, {}, format='json').status_code, 200)
        cand.refresh_from_db()
        self.assertEqual((cand.status, cand.payment_status), ('approved', 'paid'))

    def test_payer_cannot_edit_or_create_payment_records(self):
        self.nominate(transaction_reference='TXN-1')
        payment = Payment.objects.get()
        self.client.force_authenticate(user=self.voter)
        r = self.client.patch(f'/v1/payments/{payment.id}/', {'amount': '1.00'}, format='json')
        self.assertEqual(r.status_code, status.HTTP_403_FORBIDDEN)
        r = self.client.post('/v1/payments/', {
            'election': str(self.election.id), 'amount': '1.00', 'transaction_reference': 'X',
        }, format='json')
        self.assertEqual(r.status_code, status.HTTP_403_FORBIDDEN)
        payment.refresh_from_db()
        self.assertEqual(payment.amount, Decimal('500.00'))
        # Corrections still go through resubmit.
        r = self.client.post(f'/v1/payments/{payment.id}/resubmit/', {'transaction_reference': 'TXN-2'}, format='json')
        self.assertEqual(r.status_code, status.HTTP_200_OK, r.data)

    def test_member_cannot_edit_nomination_status(self):
        self.nominate(transaction_reference='TXN-1')
        cand = Candidate.objects.get()
        other = User.objects.create_user(email='other@org.test', password='Other@12345', organization=self.org,
                                         role=UserRole.VOTER)
        for user in (self.voter, other):
            self.client.force_authenticate(user=user)
            r = self.client.patch(f'{self.url}{cand.id}/', {'status': 'approved', 'payment_status': 'paid'}, format='json')
            self.assertEqual(r.status_code, status.HTTP_403_FORBIDDEN)
        cand.refresh_from_db()
        self.assertEqual((cand.status, cand.payment_status), ('submitted', 'pending_verification'))

    def test_admin_created_nomination_is_approvable(self):
        self.client.force_authenticate(user=self.admin)
        r = self.client.post(self.url, {
            'position': str(self.pos.id), 'first_name': 'Walk', 'last_name': 'In',
            'email': 'walkin@org.test', 'status': 'submitted',
        }, format='json')
        self.assertEqual(r.status_code, status.HTTP_201_CREATED, r.data)
        cand = Candidate.objects.get(email='walkin@org.test')
        self.assertEqual(cand.payment_status, 'waived')
        self.assertEqual(self.client.post(f'{self.url}{cand.id}/approve/', {}, format='json').status_code, 200)
