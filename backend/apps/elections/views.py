from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.elections.models import Election, Position, ElectionState, ElectionNotice
from apps.elections.serializers import ElectionSerializer, PositionSerializer, ElectionStateTransitionSerializer, ElectionNoticeSerializer
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
        if self.action in ['create', 'update', 'partial_update', 'destroy', 'publish', 'advance_state', 'assign_role']:
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
            
    @action(detail=True, methods=['post'])
    def advance_state(self, request, pk=None):
        """Transition election to a specific state."""
        election = self.get_object()
        target_state = request.data.get('state')
        
        if not target_state:
            return Response({'error': 'State is required'}, status=status.HTTP_400_BAD_REQUEST)
            
        try:
            election.transition_to(target_state, triggered_by=request.user)
            log_action(f'election.state_changed', request.user.organization, request.user, {
                'election_id': str(election.id),
                'new_state': target_state
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

    @action(detail=True, methods=['get'])
    def export_voter_roll(self, request, pk=None):
        """Export the voter roll for this election."""
        import csv
        from django.http import HttpResponse
        from apps.voting.models import VoterRoll

        election = self.get_object()
        voters = VoterRoll.objects.filter(election=election).order_by('voter_id')
        
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = f'attachment; filename="voter_roll_{election.id}.csv"'
        
        writer = csv.writer(response)
        writer.writerow(['Voter ID', 'Prefix', 'First Name', 'Middle Name', 'Last Name', 'Email', 'Phone', 'Council Number', 'Citizenship Number', 'Eligible'])
        
        for v in voters:
            writer.writerow([v.voter_id, v.prefix, v.first_name, v.middle_name, v.last_name, v.email, v.phone, v.council_number, v.citizenship_number, v.is_eligible])
            
        return response

    @action(detail=True, methods=['get'])
    def turnout(self, request, pk=None):
        """Get the voter turnout list for this election."""
        from apps.voting.models import VoterRoll

        election = self.get_object()
        
        # Get all voter rolls for this election directly
        voters = VoterRoll.objects.filter(election=election)
        
        turnout_list = []
        total_voted = 0
        
        for v in voters:
            if v.has_voted:
                total_voted += 1
                
            turnout_list.append({
                'member_id': str(v.id), # Frontend expects member_id, but we map it to voter id
                'member_code': v.voter_id,
                'full_name': v.full_name,
                'email': v.email,
                'has_voted': v.has_voted,
                'voted_at': v.voted_at
            })
            
        total_eligible = voters.count()
        percentage = (total_voted / total_eligible * 100) if total_eligible > 0 else 0
        
        return Response({
            'total_eligible': total_eligible,
            'total_voted': total_voted,
            'turnout_percentage': round(percentage, 2),
            'turnout_list': turnout_list
        })

    @action(detail=True, methods=['get'], permission_classes=[IsOrgAdmin])
    def voting_activity(self, request, pk=None):
        """
        Returns hourly voting activity for the analytics bar chart.
        Aggregates VoterRoll.voted_at into hour buckets.
        Admin-only endpoint.
        """
        from apps.voting.models import VoterRoll
        from django.db.models.functions import TruncHour
        from django.db.models import Count

        election = self.get_object()

        hourly_data = (
            VoterRoll.objects
            .filter(election=election, has_voted=True, voted_at__isnull=False)
            .annotate(hour=TruncHour('voted_at'))
            .values('hour')
            .annotate(count=Count('id'))
            .order_by('hour')
        )

        activity = [
            {
                'hour': entry['hour'].strftime('%H:00') if entry['hour'] else '??:00',
                'count': entry['count'],
            }
            for entry in hourly_data
        ]

        return Response({'activity_by_hour': activity})

    @action(detail=True, methods=['post'], permission_classes=[IsOrgAdmin])
    def assign_role(self, request, pk=None):
        """Assign an election officer role to a user via email."""
        from django.contrib.auth import get_user_model
        from apps.elections.models import ElectionRoleAssignment

        election = self.get_object()
        email = request.data.get('email')
        role = request.data.get('role', 'election_officer')

        if not email:
            return Response({'error': 'Email is required.'}, status=status.HTTP_400_BAD_REQUEST)

        User = get_user_model()
        try:
            user_to_assign = User.objects.get(email=email, organization=request.user.organization)
        except User.DoesNotExist:
            return Response({'error': 'User not found in this organization.'}, status=status.HTTP_404_NOT_FOUND)

        assignment, created = ElectionRoleAssignment.objects.get_or_create(
            user=user_to_assign,
            election=election,
            role=role,
            defaults={'assigned_by': request.user}
        )

        return Response({
            'message': f'Role {role} assigned to {email}',
            'created': created
        }, status=status.HTTP_200_OK if not created else status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'], permission_classes=[IsOrgAdmin])
    def broadcast_email(self, request, pk=None):
        """Send a custom email to all eligible voters in the election."""
        election = self.get_object()
        subject = request.data.get('subject')
        body_html = request.data.get('body_html')
        
        if not subject or not body_html:
            return Response({'error': 'subject and body_html are required.'}, status=status.HTTP_400_BAD_REQUEST)
            
        from apps.voting.models import VoterRoll
        from apps.notifications.services import NotificationService
        
        voters = VoterRoll.objects.filter(election=election, is_eligible=True)
        sent_count = 0
        
        for voter in voters:
            NotificationService.send_custom_email(
                to_email=voter.email,
                subject=subject,
                election=election,
                body_html=body_html
            )
            sent_count += 1
            
        log_action('election.email_broadcast', request.user.organization, request.user, {
            'election_id': str(election.id),
            'sent_count': sent_count,
            'subject': subject
        })
        
        return Response({'message': f'Sent {sent_count} emails.'}, status=status.HTTP_200_OK)


class ElectionNoticeViewSet(viewsets.ModelViewSet):
    """
    Manage notices for an election.
    """
    serializer_class = ElectionNoticeSerializer
    
    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsOrgAdmin()]
        return [IsObserver()]

    def get_queryset(self):
        return ElectionNotice.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )

    def perform_create(self, serializer):
        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )
        serializer.save(election=election)


class PositionViewSet(viewsets.ModelViewSet):
    serializer_class = PositionSerializer
    
    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsElectionOfficer()]
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
        self.check_object_permissions(self.request, election)
        serializer.save(election=election)
