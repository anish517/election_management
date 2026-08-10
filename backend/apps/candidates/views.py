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
        return Candidate.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )

    def perform_create(self, serializer):
        from apps.elections.models import Election
        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )
        
        # If an officer creates it, they can specify the status, otherwise it auto-approves.
        # If a standard user self-nominates, it's always SUBMITTED.
        if self.request.user.is_org_admin: # or check officer role
            status_val = serializer.validated_data.get('status', NominationStatus.APPROVED)
            serializer.save(
                election=election,
                status=status_val,
                reviewed_by=self.request.user if status_val == NominationStatus.APPROVED else None,
                reviewed_at=timezone.now() if status_val == NominationStatus.APPROVED else None,
                review_notes="Admin created" if status_val == NominationStatus.APPROVED else ""
            )
        else:
            # Self-nomination by a voter: enforce their own member record
            member = self.request.user.organization.members.filter(email=self.request.user.email).first()
            if not member:
                from rest_framework.exceptions import ValidationError
                raise ValidationError({'error': 'You do not have a linked member profile in this organization to run as a candidate.'})

            from django.db import IntegrityError
            try:
                serializer.save(
                    election=election,
                    status=NominationStatus.SUBMITTED,
                    member=member
                )
            except IntegrityError:
                from rest_framework.exceptions import ValidationError
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
