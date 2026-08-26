from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.candidates.models import Candidate, NominationStatus
from apps.candidates.serializers import CandidateSerializer
from apps.elections.permissions import IsElectionOfficer
from apps.audit.models import log_action

class CandidateViewSet(viewsets.ModelViewSet):
    """
    Manage candidate nominations.
    """
    serializer_class = CandidateSerializer
    
    def get_permissions(self):
        from rest_framework.permissions import IsAuthenticated
        if self.action in ['approve', 'reject']:
            return [IsElectionOfficer()]
        # Anyone can view candidates or submit a nomination (if election state allows)
        return [IsAuthenticated()]

    def get_queryset(self):
        qs = Candidate.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )
        if self.request.user.role == 'candidate':
            qs = qs.filter(email__iexact=self.request.user.email)
        return qs

    def perform_create(self, serializer):
        from apps.elections.models import Election, ElectionCommittee, ElectionRoleAssignment
        from rest_framework.exceptions import PermissionDenied, ValidationError
        from django.db import IntegrityError
        from apps.voting.models import VoterRoll
        from apps.members.models import Member

        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )

        user_email = self.request.user.email.strip().lower()
        payload_email = (self.request.data.get('email') or '').strip().lower()
        
        # Check if this is an Admin creating a candidate for someone else via Admin Panel
        is_admin_manual_create = (
            (self.request.user.role in ['org_admin', 'super_admin'] or getattr(self.request.user, 'is_org_admin', False))
            and payload_email
            and payload_email != user_email
            and 'first_name' in self.request.data
        )

        if is_admin_manual_create:
            status_val = serializer.validated_data.get('status', NominationStatus.APPROVED)
            serializer.save(
                election=election,
                status=status_val,
                reviewed_by=self.request.user if status_val == NominationStatus.APPROVED else None,
                reviewed_at=timezone.now() if status_val == NominationStatus.APPROVED else None,
                review_notes="Admin created" if status_val == NominationStatus.APPROVED else ""
            )
            return

        # Conflict of Interest Check for Self-Nomination:
        # Election Officers, Observers, Auditors, Committee Members, and Org Admins CANNOT run as candidates
        is_restricted_role = (
            self.request.user.role in ['election_officer', 'observer', 'auditor', 'org_admin', 'super_admin']
            or ElectionRoleAssignment.objects.filter(
                user=self.request.user, election=election,
                role__in=['election_officer', 'observer', 'auditor']
            ).exists()
            or ElectionCommittee.objects.filter(
                election=election, chair_email__iexact=user_email
            ).exists()
        )

        if is_restricted_role:
            raise PermissionDenied(
                "Conflict of Interest: Election Officers, Observers, Auditors, and Election Committee members are not eligible to run as candidates or submit nominations in this election."
            )

        try:
            voter = VoterRoll.objects.filter(election=election, email__iexact=user_email).first()
            if not voter and self.request.user.phone:
                voter = VoterRoll.objects.filter(election=election, phone=self.request.user.phone).first()

            member = Member.objects.filter(organization=election.organization, email__iexact=user_email).first()

            first_name = voter.first_name if voter else (member.first_name if member else '')
            middle_name = voter.middle_name if voter else ''
            last_name = voter.last_name if voter else (member.last_name if member else '')
            phone = voter.phone if voter else (member.phone if member else self.request.user.phone)

            # Calculate applicable fee
            pos = serializer.validated_data.get('position')
            pos_charge = float(pos.nominee_charge or 0.0) if pos else 0.0
            el_charge = float(election.nominee_charge or 0.0)
            ps = election.organization.payment_settings or {}
            default_fee = float(ps.get('default_nomination_fee', 0.0) or 0.0)
            fee = pos_charge if pos_charge > 0 else (el_charge if el_charge > 0 else default_fee)

            is_payment_enabled = bool(ps.get('is_payment_enabled', False) or election.is_paid_candidacy)
            txn_ref = (self.request.data.get('transaction_reference') or self.request.data.get('transaction_id') or '').strip()
            receipt_url = (self.request.data.get('receipt_image_url') or self.request.data.get('receipt_url') or '').strip()
            pay_notes = (self.request.data.get('payment_notes') or '').strip()
            pay_method = self.request.data.get('payment_method') or 'static_qr_bank'

            initial_payment_status = 'waived'
            if (is_payment_enabled and fee > 0) or txn_ref:
                initial_payment_status = 'pending_verification'

            candidate = serializer.save(
                election=election,
                status=NominationStatus.SUBMITTED,
                payment_status=initial_payment_status,
                email=user_email,
                first_name=first_name,
                middle_name=middle_name,
                last_name=last_name,
                contact_number=phone or '',
            )

            # If payment is active or transaction reference provided, create Payment ledger record
            if (is_payment_enabled and fee > 0) or txn_ref:
                from apps.billing.models import Payment, PaymentStatus
                Payment.objects.create(
                    organization=election.organization,
                    election=election,
                    candidate=candidate,
                    user=self.request.user,
                    amount=fee if fee > 0 else 0.00,
                    payment_method=pay_method,
                    transaction_reference=txn_ref,
                    receipt_image_url=receipt_url,
                    payment_notes=pay_notes,
                    status=PaymentStatus.PENDING,
                )
        except IntegrityError:
            raise ValidationError({'error': 'You have already submitted a nomination for this position.'})

    @action(detail=True, methods=['post'])
    def approve(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        notes = request.data.get('notes', '')

        if candidate.status not in [NominationStatus.SUBMITTED, NominationStatus.UNDER_REVIEW]:
            return Response({'error': 'Can only approve submitted nominations.'}, status=400)

        candidate.status = NominationStatus.APPROVED
        candidate.reviewed_by = request.user
        candidate.review_notes = notes
        candidate.reviewed_at = timezone.now()
        candidate.save()

        log_action('candidate.approved', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk)
        })

        # 📧 Notify the candidate their nomination was approved
        from apps.notifications.tasks import send_candidate_approved_notification
        send_candidate_approved_notification.delay(str(election_pk), str(candidate.id))

        return Response(self.get_serializer(candidate).data)


    @action(detail=True, methods=['post'])
    def reject(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        notes = request.data.get('notes', '')
        
        if not notes:
            return Response({'error': 'Review notes are required for rejection.'}, status=400)
            
        candidate.status = NominationStatus.REJECTED
        candidate.reviewed_by = request.user
        candidate.review_notes = notes
        candidate.reviewed_at = timezone.now()
        candidate.save()
        
        log_action('candidate.rejected', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk)
        })
        
        return Response(self.get_serializer(candidate).data)

    @action(detail=True, methods=['post'])
    def withdraw(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        reason = request.data.get('reason', '')

        user = request.user
        user_email = user.email.strip().lower() if user.email else ''
        cand_email = candidate.email.strip().lower() if candidate.email else ''
        is_owner = bool(cand_email and cand_email == user_email)
        is_officer = user.role in ['org_admin', 'election_officer', 'super_admin'] or getattr(user, 'is_org_admin', False)

        if not (is_owner or is_officer):
            raise PermissionDenied('Only the candidate or an election officer can withdraw this nomination.')

        candidate.status = NominationStatus.WITHDRAWN
        candidate.review_notes = f"Withdrawn: {reason}" if reason else "Candidate nomination withdrawn"
        candidate.save()

        log_action('candidate.withdrawn', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk),
            'reason': reason,
        })

        from apps.notifications.services import NotificationService
        try:
            NotificationService.notify_candidate_withdrawn(candidate.election, candidate, reason=reason)
        except Exception as e:
            logger.warning(f"Failed to send candidate withdrawal notification: {e}")

        return Response(self.get_serializer(candidate).data)


class CandidateObjectionViewSet(viewsets.ModelViewSet):
    """
    CRUD and review for Candidate Eligibility Objections.
    """
    from rest_framework.permissions import IsAuthenticated
    permission_classes = [IsAuthenticated]
    from apps.candidates.serializers import CandidateObjectionSerializer
    serializer_class = CandidateObjectionSerializer

    def get_queryset(self):
        from apps.candidates.models import CandidateObjection
        election_pk = self.kwargs.get('election_pk')
        user = self.request.user
        qs = CandidateObjection.objects.filter(election_id=election_pk, election__organization=user.organization)

        is_officer = (
            user.role in ['org_admin', 'election_officer', 'super_admin']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            qs = qs.filter(claimant_email__iexact=user.email.strip().lower())
        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        from django.utils import timezone
        from apps.elections.models import Election
        from rest_framework.exceptions import ValidationError, PermissionDenied

        user = self.request.user
        if user.role in ['observer', 'auditor']:
            raise PermissionDenied('Observers and Auditors have read-only monitoring access and cannot file candidate objections.')

        election_pk = self.kwargs.get('election_pk')
        election = Election.objects.get(id=election_pk, organization=user.organization)
        now = timezone.now()

        # Schedule Gating: Objections open after nomination closes and before candidacy claim deadline
        if election.nomination_close_at and now < election.nomination_close_at:
            raise ValidationError({'detail': 'Candidate objection window opens after nominations close.'})
        if election.candidacy_claim_date and now > election.candidacy_claim_date:
            raise ValidationError({'detail': 'Candidate objection deadline has passed.'})

        serializer.save(
            election=election,
            claimant_name=serializer.validated_data.get('claimant_name') or self.request.user.full_name or self.request.user.email,
            claimant_email=serializer.validated_data.get('claimant_email') or self.request.user.email,
        )

    @action(detail=True, methods=['post'])
    def resolve(self, request, election_pk=None, pk=None):
        """
        Election Officer resolves candidate objection (Upheld / Dismissed).
        """
        from apps.elections.permissions import IsElectionOfficer
        if not IsElectionOfficer().has_permission(request, self):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        objection = self.get_object()
        new_status = request.data.get('status')
        if new_status not in ['upheld', 'dismissed']:
            return Response({'detail': "Status must be 'upheld' or 'dismissed'."}, status=status.HTTP_400_BAD_REQUEST)

        notes = request.data.get('resolution_notes', '')
        objection.status = new_status
        objection.resolution_notes = notes
        objection.resolved_by = request.user
        objection.resolved_at = timezone.now()
        objection.save()

        # If objection is upheld, reject/disqualify the candidate
        if new_status == 'upheld':
            objection.candidate.status = NominationStatus.REJECTED
            objection.candidate.review_notes = f"Objection Upheld: {notes or objection.objection_reason}"
            objection.candidate.reviewed_by = request.user
            objection.candidate.reviewed_at = timezone.now()
            objection.candidate.save(update_fields=['status', 'review_notes', 'reviewed_by', 'reviewed_at'])

        log_action('candidate_objection.resolved', objection.election.organization, request.user, {
            'election_id': str(objection.election.id),
            'candidate_id': str(objection.candidate.id),
            'objection_id': str(objection.id),
            'status': objection.status
        })
        from apps.candidates.serializers import CandidateObjectionSerializer
        return Response(CandidateObjectionSerializer(objection).data)
