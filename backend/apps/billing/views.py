from django.utils import timezone
from django.db.models import Sum, Count, Q
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied, ValidationError

from apps.billing.models import Payment, PaymentStatus, PaymentMethod
from apps.billing.serializers import (
    PaymentSerializer,
    PaymentVerificationSerializer,
    PaymentRejectionSerializer,
    PaymentResubmitSerializer,
    PaymentCorrectionSerializer,
)
from apps.audit.models import log_action


class PaymentViewSet(viewsets.ModelViewSet):
    """
    CRUD and officer verification for Static QR payments.
    """
    serializer_class = PaymentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        org = user.organization
        qs = Payment.objects.filter(organization=org).select_related(
            'election', 'candidate', 'candidate__position', 'user', 'reviewed_by'
        )

        is_officer = (
            user.role in ['org_admin', 'super_admin', 'election_officer', 'observer', 'auditor']
            or getattr(user, 'is_org_admin', False)
        )

        # Candidates / regular members see only their own payment records
        if not is_officer:
            user_email = (user.email or '').strip().lower()
            qs = qs.filter(Q(user=user) | Q(candidate__email__iexact=user_email))

        # Query filters
        election_id = self.request.query_params.get('election') or self.request.query_params.get('election_id')
        if election_id:
            qs = qs.filter(election_id=election_id)

        status_param = self.request.query_params.get('status')
        if status_param and status_param.lower() != 'all':
            qs = qs.filter(status=status_param.lower())

        q = self.request.query_params.get('q')
        if q:
            qs = qs.filter(
                Q(transaction_reference__icontains=q)
                | Q(user__email__icontains=q)
                | Q(user__first_name__icontains=q)
                | Q(user__last_name__icontains=q)
                | Q(candidate__first_name__icontains=q)
                | Q(candidate__last_name__icontains=q)
            )

        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        serializer.save(
            organization=self.request.user.organization,
            user=self.request.user,
            status=PaymentStatus.PENDING,
        )

    @action(detail=True, methods=['post'])
    def verify(self, request, pk=None):
        """
        Election Officer or Admin marks a Static QR payment as Verified/Approved.
        """
        user = request.user
        is_officer = (
            user.role in ['org_admin', 'super_admin', 'election_officer']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            raise PermissionDenied("Only Election Officers and Administrators can verify payments.")

        payment = self.get_object()
        serializer = PaymentVerificationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        notes = serializer.validated_data.get('notes', '')

        payment.status = PaymentStatus.VERIFIED
        payment.reviewed_by = user
        payment.reviewed_at = timezone.now()
        if notes:
            payment.payment_notes = f"{payment.payment_notes}\n[Verification Note]: {notes}".strip()
        payment.save()

        # Update candidate payment status if linked
        if payment.candidate:
            candidate = payment.candidate
            candidate.payment_status = 'paid'
            candidate.save(update_fields=['payment_status', 'updated_at'])

        log_action(
            'payment.verified',
            payment.organization,
            user,
            target=payment,
            metadata={
                'payment_id': str(payment.id),
                'amount': str(payment.amount),
                'transaction_reference': payment.transaction_reference,
                'candidate_id': str(payment.candidate.id) if payment.candidate else None,
                'election_id': str(payment.election.id) if payment.election else None,
            },
        )

        return Response(PaymentSerializer(payment).data)

    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        """
        Election Officer or Admin rejects a payment proof with a reason.
        """
        user = request.user
        is_officer = (
            user.role in ['org_admin', 'super_admin', 'election_officer']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            raise PermissionDenied("Only Election Officers and Administrators can reject payments.")

        payment = self.get_object()
        serializer = PaymentRejectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        reason = serializer.validated_data['reason']

        payment.status = PaymentStatus.REJECTED
        payment.rejection_reason = reason
        payment.reviewed_by = user
        payment.reviewed_at = timezone.now()
        payment.save()

        if payment.candidate:
            candidate = payment.candidate
            candidate.payment_status = 'unpaid'
            candidate.save(update_fields=['payment_status', 'updated_at'])

        log_action(
            'payment.rejected',
            payment.organization,
            user,
            target=payment,
            metadata={
                'payment_id': str(payment.id),
                'reason': reason,
                'candidate_id': str(payment.candidate.id) if payment.candidate else None,
            },
        )

        return Response(PaymentSerializer(payment).data)

    @action(detail=True, methods=['post'])
    def resubmit(self, request, pk=None):
        """
        Payer or Candidate resubmits updated voucher and transaction reference.
        """
        payment = self.get_object()
        user = request.user
        is_owner = payment.user == user or (payment.candidate and payment.candidate.email.lower() == user.email.lower())
        if not is_owner and user.role not in ['org_admin', 'super_admin']:
            raise PermissionDenied("Only the payment submitter can resubmit payment proof.")

        serializer = PaymentResubmitSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        payment.transaction_reference = serializer.validated_data['transaction_reference']
        if serializer.validated_data.get('receipt_image_url'):
            payment.receipt_image_url = serializer.validated_data['receipt_image_url']
        if serializer.validated_data.get('payment_notes'):
            payment.payment_notes = serializer.validated_data['payment_notes']
        payment.status = PaymentStatus.PENDING
        payment.rejection_reason = ''
        payment.reviewed_by = None
        payment.reviewed_at = None
        payment.save()

        if payment.candidate:
            payment.candidate.payment_status = 'pending_verification'
            payment.candidate.save(update_fields=['payment_status', 'updated_at'])

        return Response(PaymentSerializer(payment).data)

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """
        Aggregated statistics for Admin Payment Dashboard.
        """
        user = request.user
        org = user.organization
        election_id = request.query_params.get('election') or request.query_params.get('election_id')

        qs = Payment.objects.filter(organization=org)
        if election_id:
            qs = qs.filter(election_id=election_id)

        is_officer = (
            user.role in ['org_admin', 'super_admin', 'election_officer', 'observer', 'auditor']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            qs = qs.filter(Q(user=user) | Q(candidate__email__iexact=user.email.strip().lower()))

        total_collected = qs.filter(status__in=[PaymentStatus.VERIFIED, PaymentStatus.COMPLETED]).aggregate(
            total=Sum('amount')
        )['total'] or 0.0

        pending_agg = qs.filter(status=PaymentStatus.PENDING).aggregate(
            count=Count('id'), total=Sum('amount')
        )
        verified_agg = qs.filter(status__in=[PaymentStatus.VERIFIED, PaymentStatus.COMPLETED]).aggregate(
            count=Count('id'), total=Sum('amount')
        )
        rejected_count = qs.filter(status=PaymentStatus.REJECTED).count()

        return Response({
            'total_collected': float(total_collected),
            'pending_count': pending_agg['count'] or 0,
            'pending_amount': float(pending_agg['total'] or 0.0),
            'verified_count': verified_agg['count'] or 0,
            'verified_amount': float(verified_agg['total'] or 0.0),
            'rejected_count': rejected_count,
            'total_transactions': qs.count(),
        })

    @action(detail=True, methods=['post'])
    def request_correction(self, request, pk=None):
        """
        Admin/Officer requests a correction from the candidate for a payment.
        Sets status back to 'pending' and saves correction notes and history.
        """
        user = request.user
        is_officer = (
            user.role in ['org_admin', 'super_admin', 'election_officer']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            raise PermissionDenied('Only election officers can request payment corrections.')

        payment = self.get_object()
        serializer = PaymentCorrectionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        notes = serializer.validated_data['correction_notes']

        # Append to correction_history
        history_entry = {
            'date': timezone.now().isoformat(),
            'by': user.email,
            'note': notes,
            'status_before': payment.status,
        }
        current_history = payment.correction_history or []
        current_history.append(history_entry)

        payment.correction_notes = notes
        payment.correction_history = current_history
        payment.status = PaymentStatus.PENDING
        payment.save(update_fields=['correction_notes', 'correction_history', 'status'])

        log_action('payment.correction_requested', user.organization, user, {
            'payment_id': str(payment.id),
            'correction_notes': notes,
        })

        return Response(PaymentSerializer(payment).data)
