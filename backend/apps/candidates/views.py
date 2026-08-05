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
        # In a full implementation, voters should be able to submit their own nominations,
        # but for this iteration, let's keep it simple: Election Officers manage candidates.
        return [IsElectionOfficer()]

    def get_queryset(self):
        return Candidate.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )

    def perform_create(self, serializer):
        serializer.save()

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
