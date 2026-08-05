from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.elections.models import Election, Position, ElectionState
from apps.elections.serializers import ElectionSerializer, PositionSerializer, ElectionStateTransitionSerializer
from apps.core.permissions import IsOrgAdmin
from apps.elections.permissions import IsElectionOfficer, IsObserver
from apps.audit.models import log_action

class ElectionViewSet(viewsets.ModelViewSet):
    """
    Manage elections for the organization.
    (doc: 21-REST-API-Documentation.md)
    """
    serializer_class = ElectionSerializer
    
    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy', 'publish']:
            return [IsOrgAdmin()]
        return [IsObserver()]

    def get_queryset(self):
        # Always scope to the user's organization
        return Election.objects.filter(organization=self.request.user.organization)

    def perform_create(self, serializer):
        election = serializer.save(
            organization=self.request.user.organization,
            created_by=self.request.user
        )
        log_action('election.created', self.request.user.organization, self.request.user, {
            'election_id': str(election.id),
            'title': election.title
        })
        
    @action(detail=True, methods=['post'])
    def publish(self, request, pk=None):
        """Transition election from DRAFT to PUBLISHED."""
        election = self.get_object()
        
        try:
            election.transition_to(ElectionState.PUBLISHED, triggered_by=request.user)
            log_action('election.published', request.user.organization, request.user, {
                'election_id': str(election.id)
            })
            return Response(self.get_serializer(election).data)
        except ValueError as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
            
    @action(detail=True, methods=['get'])
    def history(self, request, pk=None):
        """Get the state transition history."""
        election = self.get_object()
        transitions = election.state_transitions.all()
        serializer = ElectionStateTransitionSerializer(transitions, many=True)
        return Response(serializer.data)


class PositionViewSet(viewsets.ModelViewSet):
    serializer_class = PositionSerializer
    
    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsOrgAdmin()]
        return [IsObserver()]

    def get_queryset(self):
        return Position.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )

    def perform_create(self, serializer):
        # We need to get the election
        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )
        serializer.save(election=election)
