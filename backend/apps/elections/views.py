from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from apps.elections.models import Election, Position, PositionQuota, ElectionState, ElectionNotice, ElectionCommittee
from apps.elections.serializers import (
    ElectionSerializer, PositionSerializer, PositionQuotaSerializer,
    ElectionStateTransitionSerializer, ElectionNoticeSerializer, ElectionCommitteeSerializer
)
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
        if self.action in [
            'create', 'update', 'partial_update', 'destroy',
            'publish', 'advance_state', 'assign_role', 'broadcast_email',
            'create_committee', 'committees', 'assignments',
            'update_committee', 'delete_committee',
        ]:
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

    @action(detail=True, methods=['get'], permission_classes=[IsOrgAdmin])
    def committees(self, request, pk=None):
        """List all committees for this election."""
        election = self.get_object()
        qs = ElectionCommittee.objects.filter(election=election).order_by('-created_at')
        serializer = ElectionCommitteeSerializer(qs, many=True)
        return Response({'results': serializer.data})

    @action(detail=True, methods=['post'], permission_classes=[IsOrgAdmin],
            parser_classes=[MultiPartParser, FormParser, JSONParser])
    def create_committee(self, request, pk=None):
        """Create a new committee and optionally create/link a chair user account.
        Supports roles: election_officer (default), observer, auditor.
        """
        from django.contrib.auth import get_user_model
        from apps.elections.models import ElectionRoleAssignment

        election = self.get_object()
        data = request.data
        committee_type = data.get('committee_type', 'new')
        committee_name = data.get('committee_name', '').strip()
        chair_designation = data.get('chair_designation', '').strip()
        chair_contact = data.get('chair_contact', '').strip()
        chair_email = data.get('chair_email', '').strip().lower()
        password = data.get('password', '')
        chair_signature = request.FILES.get('chair_signature')

        # Role for the committee member — defaults to election_officer
        VALID_ROLES = ['election_officer', 'observer', 'auditor']
        assigned_role = data.get('role', 'election_officer').strip()
        if assigned_role not in VALID_ROLES:
            return Response(
                {'error': f'Invalid role. Choose from: {", ".join(VALID_ROLES)}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not committee_name or not chair_email:
            return Response({'error': 'committee_name and chair_email are required.'}, status=status.HTTP_400_BAD_REQUEST)

        User = get_user_model()

        if committee_type == 'new':
            if not password:
                return Response({'error': 'password is required when creating a new committee.'}, status=status.HTTP_400_BAD_REQUEST)
            if User.objects.filter(email=chair_email).exists():
                return Response({'error': f'A user with email {chair_email} already exists.'}, status=status.HTTP_400_BAD_REQUEST)
            chair_user = User.objects.create_user(
                email=chair_email,
                password=password,
                organization=request.user.organization,
                role=assigned_role,
            )
        else:
            # Select existing user from this org
            try:
                chair_user = User.objects.get(email=chair_email, organization=request.user.organization)
                # Update their role to the selected one if different
                if chair_user.role != assigned_role:
                    chair_user.role = assigned_role
                    chair_user.save(update_fields=['role'])
            except User.DoesNotExist:
                return Response({'error': 'No user with that email found in this organization.'}, status=status.HTTP_404_NOT_FOUND)

        committee = ElectionCommittee.objects.create(
            election=election,
            committee_type=committee_type,
            committee_name=committee_name,
            chair_designation=chair_designation,
            chair_contact=chair_contact,
            chair_email=chair_email,
            chair_signature=chair_signature,
            chair_user=chair_user,
            role=assigned_role,
            created_by=request.user,
        )

        # Auto-assign the selected role for this election
        ElectionRoleAssignment.objects.get_or_create(
            user=chair_user,
            election=election,
            role=assigned_role,
            defaults={'assigned_by': request.user}
        )

        log_action('election.committee_created', request.user.organization, request.user, {
            'election_id': str(election.id),
            'committee_name': committee_name,
            'chair_email': chair_email,
            'role': assigned_role,
        })

        serializer = ElectionCommitteeSerializer(committee)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['patch'], permission_classes=[IsOrgAdmin],
            parser_classes=[MultiPartParser, FormParser, JSONParser],
            url_path='committees/(?P<committee_id>[^/.]+)/update')
    def update_committee(self, request, pk=None, committee_id=None):
        """Partially update an existing committee record."""
        election = self.get_object()
        try:
            committee = ElectionCommittee.objects.get(pk=committee_id, election=election)
        except ElectionCommittee.DoesNotExist:
            return Response({'error': 'Committee not found.'}, status=status.HTTP_404_NOT_FOUND)

        updatable = ['committee_name', 'chair_designation', 'chair_contact']
        for field in updatable:
            if field in request.data:
                setattr(committee, field, request.data[field])

        if 'chair_signature' in request.FILES:
            committee.chair_signature = request.FILES['chair_signature']

        # Update role on committee model
        if 'role' in request.data:
            new_role = request.data['role']
            VALID_ROLES = ['election_officer', 'observer', 'auditor']
            if new_role in VALID_ROLES:
                committee.role = new_role

        committee.save()

        # Sync role to user account and role assignment
        if 'role' in request.data:
            new_role = request.data['role']
            VALID_ROLES = ['election_officer', 'observer', 'auditor']
            if new_role in VALID_ROLES and committee.chair_user:
                from apps.elections.models import ElectionRoleAssignment
                committee.chair_user.role = new_role
                committee.chair_user.save(update_fields=['role'])
                ElectionRoleAssignment.objects.update_or_create(
                    user=committee.chair_user,
                    election=election,
                    defaults={'role': new_role, 'assigned_by': request.user},
                )

        serializer = ElectionCommitteeSerializer(committee)
        return Response(serializer.data)

    @action(detail=True, methods=['delete'], permission_classes=[IsOrgAdmin],
            url_path='committees/(?P<committee_id>[^/.]+)/delete')
    def delete_committee(self, request, pk=None, committee_id=None):
        """Delete a committee record.

        Also:
        - Removes the ElectionRoleAssignment for this user/election
        - If the user was created specifically for this committee (committee_type='new'),
          deactivates their account so they can no longer log in.
        """
        from apps.elections.models import ElectionRoleAssignment

        election = self.get_object()
        try:
            committee = ElectionCommittee.objects.get(pk=committee_id, election=election)
        except ElectionCommittee.DoesNotExist:
            return Response({'error': 'Committee not found.'}, status=status.HTTP_404_NOT_FOUND)

        chair_user = committee.chair_user

        # Always revoke the election-specific role assignment
        if chair_user:
            ElectionRoleAssignment.objects.filter(
                user=chair_user,
                election=election,
            ).delete()

            # If this user was created solely for this committee, deactivate them
            # so they cannot log in anymore
            if committee.committee_type == 'new':
                chair_user.is_active = False
                chair_user.save(update_fields=['is_active'])

        committee.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


    @action(detail=True, methods=['get'], permission_classes=[IsOrgAdmin])
    def assignments(self, request, pk=None):
        """List all role assignments for this election."""
        from apps.elections.models import ElectionRoleAssignment
        election = self.get_object()
        qs = ElectionRoleAssignment.objects.filter(election=election).select_related('user').order_by('role', 'user__email')
        data = [
            {
                'id': str(a.id),
                'role': a.role,
                'user': {
                    'email': a.user.email,
                }
            }
            for a in qs
        ]
        return Response({'results': data})

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
        from apps.notifications.tasks import send_custom_broadcast_email_task
        
        # Calculate expected recipient count (for log and response)
        voter_count = VoterRoll.objects.filter(election=election, is_eligible=True).count()
        
        # Dispatch Celery task
        send_custom_broadcast_email_task.delay(
            str(election.id),
            subject,
            body_html,
        )
        
        log_action('election.email_broadcast', request.user.organization, request.user, {
            'election_id': str(election.id),
            'queued_count': voter_count,
            'subject': subject
        })
        
        return Response({'message': f'Queued {voter_count} emails for sending.'}, status=status.HTTP_200_OK)


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
        qs = ElectionNotice.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )
        if not self.request.user.is_org_admin:
            qs = qs.filter(is_published=True)
        return qs.order_by('-created_at')

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


class PositionQuotaViewSet(viewsets.ModelViewSet):
    serializer_class = PositionQuotaSerializer

    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsElectionOfficer()]
        return [IsObserver()]

    def get_queryset(self):
        qs = PositionQuota.objects.filter(
            position__election__organization=self.request.user.organization,
            position__election_id=self.kwargs['election_pk']
        ).select_related('position')
        
        position_id = self.request.query_params.get('position')
        if position_id:
            qs = qs.filter(position_id=position_id)
        return qs

    def perform_create(self, serializer):
        position_id = self.request.data.get('position')
        position = Position.objects.get(
            id=position_id,
            election_id=self.kwargs['election_pk'],
            election__organization=self.request.user.organization
        )
        self.check_object_permissions(self.request, position.election)
        serializer.save(position=position)

