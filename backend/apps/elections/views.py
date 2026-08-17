from rest_framework import viewsets, status, permissions
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

def _advance_due_elections(organization=None):
    """
    Evaluates due schedule dates and transitions election states + sends emails.
    Runs on API access to guarantee real-time lifecycle progression even if Celery worker is offline.
    """
    from django.utils import timezone
    from apps.elections.models import Election, ElectionState
    from apps.notifications.services import NotificationService
    from apps.notifications.models import EmailBroadcastLog
    import logging
    logger = logging.getLogger(__name__)

    now = timezone.now()
    qs = Election.objects.all()
    if organization:
        qs = qs.filter(organization=organization)

    # 1. First Voter List Date passed -> Notify First Voter Roll Published
    # Strictly ONLY when in PUBLISHED state and BEFORE final list / nominations
    voter_list_due = qs.filter(
        state=ElectionState.PUBLISHED,
        first_voter_list_date__isnull=False,
        first_voter_list_date__lte=now,
    ).exclude(
        nomination_open_at__isnull=False,
        nomination_open_at__lte=now,
    )
    for el in voter_list_due:
        already_sent = EmailBroadcastLog.objects.filter(
            election=el,
            subject__icontains='First Voter List Published'
        ).exists() or EmailBroadcastLog.objects.filter(
            election=el,
            subject__icontains='Voter List Published'
        ).exists()
        if not already_sent:
            try:
                NotificationService.notify_voter_list_published(el)
            except Exception as e:
                logger.warning(f"[AutoAdvance] Voter list notify failed for {el.id}: {e}")

    # 1b. Final Voter List Date passed -> Notify Final Certified Voter Roll
    final_voter_list_due = qs.filter(
        state__in=[ElectionState.PUBLISHED, ElectionState.NOMINATION_OPEN],
        final_voter_list_date__isnull=False,
        final_voter_list_date__lte=now,
    )
    for el in final_voter_list_due:
        already_sent = EmailBroadcastLog.objects.filter(
            election=el,
            subject__icontains='Final Voter List Published'
        ).exists()
        if not already_sent:
            try:
                NotificationService.notify_final_voter_list_published(el)
            except Exception as e:
                logger.warning(f"[AutoAdvance] Final voter list notify failed for {el.id}: {e}")

    # 2. PUBLISHED -> NOMINATION_OPEN
    nom_open_due = qs.filter(
        state=ElectionState.PUBLISHED,
        nomination_open_at__isnull=False,
        nomination_open_at__lte=now,
    )
    for el in nom_open_due:
        try:
            el.transition_to(ElectionState.NOMINATION_OPEN)
            NotificationService.notify_nomination_open(el)
        except Exception as e:
            logger.warning(f"[AutoAdvance] NOMINATION_OPEN failed for {el.id}: {e}")

    # 3. NOMINATION_OPEN -> NOMINATION_CLOSED
    nom_close_due = qs.filter(
        state=ElectionState.NOMINATION_OPEN,
        nomination_close_at__isnull=False,
        nomination_close_at__lte=now,
    )
    for el in nom_close_due:
        try:
            el.transition_to(ElectionState.NOMINATION_CLOSED)
            NotificationService.notify_candidacy_claim_published(el)
        except Exception as e:
            logger.warning(f"[AutoAdvance] NOMINATION_CLOSED failed for {el.id}: {e}")

    # 3a. Nominations closed -> Notify Preliminary Candidate List & Scrutiny/Objections open
    cand_claims_due = qs.filter(
        state=ElectionState.NOMINATION_CLOSED,
        nomination_close_at__isnull=False,
        nomination_close_at__lte=now,
    )
    for el in cand_claims_due:
        already_sent = EmailBroadcastLog.objects.filter(
            election=el,
            subject__icontains='Candidate List Published (Claims Open)'
        ).exists()
        if not already_sent:
            try:
                NotificationService.notify_candidacy_claim_published(el)
            except Exception as e:
                logger.warning(f"[AutoAdvance] Candidacy claims notify failed for {el.id}: {e}")

    # 3b. Final Candidate List Date passed -> Notify Final Approved Candidates
    final_cand_due = qs.filter(
        state__in=[ElectionState.NOMINATION_CLOSED, ElectionState.VOTING_OPEN],
        candidacy_final_date__isnull=False,
        candidacy_final_date__lte=now,
    )
    for el in final_cand_due:
        already_sent = EmailBroadcastLog.objects.filter(
            election=el,
            subject__icontains='Final Candidate List Published'
        ).exists()
        if not already_sent:
            try:
                NotificationService.notify_final_candidates_published(el)
            except Exception as e:
                logger.warning(f"[AutoAdvance] Final candidate list notify failed for {el.id}: {e}")

    # 4. NOMINATION_CLOSED -> VOTING_OPEN
    voting_open_due = qs.filter(
        state=ElectionState.NOMINATION_CLOSED,
        voting_start_at__isnull=False,
        voting_start_at__lte=now,
    )
    for el in voting_open_due:
        try:
            el.transition_to(ElectionState.VOTING_OPEN)
            NotificationService.notify_voting_open(el)
        except Exception as e:
            logger.warning(f"[AutoAdvance] VOTING_OPEN failed for {el.id}: {e}")

    # 5. VOTING_OPEN -> VOTING_CLOSED -> AUTO PROVISIONAL TALLY
    voting_close_due = qs.filter(
        state=ElectionState.VOTING_OPEN,
        voting_end_at__isnull=False,
        voting_end_at__lte=now,
    )
    for el in voting_close_due:
        try:
            el.transition_to(ElectionState.VOTING_CLOSED)
            NotificationService.notify_voting_closed(el)
            from apps.results.services import TallyService
            TallyService.tally_election(el)
            el.transition_to(ElectionState.RESULTS_PROVISIONAL)
        except Exception as e:
            logger.warning(f"[AutoAdvance] VOTING_CLOSED failed for {el.id}: {e}")

    # 6. RESULTS_PROVISIONAL -> RESULTS_FINAL
    # Automatically finalizes and publishes official results when contest deadline passes or voting ends
    res_final_due = qs.filter(
        state=ElectionState.RESULTS_PROVISIONAL,
    )
    for el in res_final_due:
        should_finalize = False
        if el.result_contest_deadline and el.result_contest_deadline <= now:
            should_finalize = True
        elif not el.result_contest_deadline and el.voting_end_at and el.voting_end_at <= now:
            should_finalize = True

        if should_finalize:
            try:
                el.transition_to(ElectionState.RESULTS_FINAL)
                NotificationService.notify_results_published(el)
            except Exception as e:
                logger.warning(f"[AutoAdvance] RESULTS_FINAL failed for {el.id}: {e}")


class ElectionViewSet(viewsets.ModelViewSet):
    """
    Manage elections for the organization.
    (doc: 21-REST-API-Documentation.md)
    """
    serializer_class = ElectionSerializer
    
    def get_permissions(self):
        if self.action in [
            'create', 'update', 'partial_update', 'destroy',
            'assign_role',
            'create_committee', 'committees', 'assignments',
            'update_committee', 'delete_committee',
        ]:
            return [IsOrgAdmin()]
        if self.action in [
            'publish', 'advance_state', 'broadcast_email',
            'email_logs', 'retry_failed_emails',
        ]:
            return [IsElectionOfficer()]
        return [IsObserver()]

    def get_queryset(self):
        # Auto advance any due election milestones for this organization
        if self.request.user and self.request.user.is_authenticated and self.request.user.organization:
            _advance_due_elections(self.request.user.organization)
            return Election.objects.filter(organization=self.request.user.organization)
        return Election.objects.none()

    def perform_create(self, serializer):
        org = self.request.user.organization
        kwargs = {
            'organization': org,
            'created_by': self.request.user,
        }
        if 'results_visibility' not in serializer.validated_data and org and getattr(org, 'default_result_visibility', None):
            kwargs['results_visibility'] = org.default_result_visibility

        election = serializer.save(**kwargs)
        log_action('election.created', self.request.user.organization, self.request.user, {
            'election_id': str(election.id),
            'title': election.title
        })

    def perform_update(self, serializer):
        election = serializer.save()
        log_action('election.updated', self.request.user.organization, self.request.user, {
            'election_id': str(election.id),
            'title': election.title
        })

        # If schedule dates were updated on a published election, broadcast timetable email
        schedule_fields = [
            'first_voter_list_date', 'voter_list_claim_date', 'final_voter_list_date',
            'nomination_open_at', 'nomination_close_at', 'candidacy_claim_date',
            'candidacy_final_date', 'voting_start_at', 'voting_end_at'
        ]
        has_schedule_change = any(f in serializer.validated_data for f in schedule_fields)

        if has_schedule_change and election.state != ElectionState.DRAFT:
            try:
                from apps.notifications.services import NotificationService
                NotificationService.notify_schedule_announcement(election)
            except Exception as e:
                import logging
                logging.getLogger(__name__).warning(f"[Notify] Schedule update email broadcast failed: {e}")

        # Check and advance if any new dates are already due
        _advance_due_elections(self.request.user.organization)

    @action(detail=True, methods=['post'])
    def publish(self, request, pk=None):
        """Transition election from DRAFT to PUBLISHED."""
        election = self.get_object()
        
        try:
            election.transition_to(ElectionState.PUBLISHED, triggered_by=request.user)
            log_action('election.published', request.user.organization, request.user, {
                'election_id': str(election.id)
            })

            # Broadcast schedule announcement to all voters and members
            try:
                from apps.notifications.services import NotificationService
                NotificationService.notify_schedule_announcement(election)
            except Exception as e:
                import logging
                logging.getLogger(__name__).warning(f"[Notify] Publish email broadcast failed: {e}")

            # Check if any milestones are already due immediately upon publish
            _advance_due_elections(request.user.organization)

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
            
        # Enforce Organization Governance Policy: Check if Election Officers can publish results
        if target_state in ['results_provisional', 'results_final']:
            if not getattr(request.user, 'is_org_admin', False) and getattr(request.user, 'role', '') != 'org_admin':
                if not getattr(request.user.organization, 'election_officers_can_publish', False):
                    return Response({
                        'error': 'Organization policy requires Organization Admin approval to publish election results.'
                    }, status=status.HTTP_403_FORBIDDEN)

        try:
            election.transition_to(target_state, triggered_by=request.user)
            log_action(f'election.state_changed', request.user.organization, request.user, {
                'election_id': str(election.id),
                'new_state': target_state
            })

            # Trigger background notification tasks based on state
            if target_state in ['results_provisional', 'results_final']:
                try:
                    from apps.notifications.tasks import send_results_published_notification
                    send_results_published_notification.delay(str(election.id))
                except Exception:
                    pass
            elif target_state == 'voting_closed':
                try:
                    from apps.notifications.tasks import send_voting_closed_notification
                    send_voting_closed_notification.delay(str(election.id))
                except Exception:
                    pass

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
        
        is_org_admin = request.user.role in ['org_admin', 'super_admin'] or getattr(request.user, 'is_org_admin', False)

        for v in voters:
            if v.has_voted:
                total_voted += 1
                
            entry = {
                'member_id': str(v.id), # Frontend expects member_id, but we map it to voter id
                'member_code': v.voter_id,
                'full_name': v.full_name,
                'email': v.email,
                'has_voted': v.has_voted,
                'voted_at': v.voted_at,
            }
            if is_org_admin:
                entry['voted_ip_address'] = v.voted_ip_address
                entry['voted_mac_address'] = v.voted_mac_address

            turnout_list.append(entry)
            
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
        """Create a new committee member and optionally create/link a chair user account.
        Supports selecting existing member (by member_id or email) or creating a new user.
        Supports roles: election_officer (default), observer, auditor.
        """
        from django.contrib.auth import get_user_model
        from apps.elections.models import ElectionRoleAssignment
        from apps.members.models import Member

        election = self.get_object()
        data = request.data
        committee_type = data.get('committee_type', 'existing' if data.get('member_id') else 'new')
        member_id = data.get('member_id')
        committee_name = data.get('committee_name', '').strip()
        chair_designation = data.get('chair_designation', '').strip()
        chair_contact = data.get('chair_contact', '').strip()
        chair_email = data.get('chair_email', '').strip().lower()
        password = data.get('password', '')
        chair_signature = request.FILES.get('chair_signature')
        include_in_letterhead_raw = data.get('include_in_letterhead', True)
        if isinstance(include_in_letterhead_raw, str):
            include_in_letterhead = include_in_letterhead_raw.lower() in ['true', '1', 'yes']
        else:
            include_in_letterhead = bool(include_in_letterhead_raw)

        # Role for the committee member — defaults to election_officer
        VALID_ROLES = ['election_officer', 'observer', 'auditor']
        assigned_role = data.get('role', 'election_officer').strip()
        if assigned_role not in VALID_ROLES:
            return Response(
                {'error': f'Invalid role. Choose from: {", ".join(VALID_ROLES)}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        User = get_user_model()
        chair_user = None

        if member_id:
            try:
                member = Member.objects.get(id=member_id, organization=request.user.organization)
                chair_email = member.email.strip().lower() or chair_email
                if not committee_name:
                    committee_name = member.full_name or chair_email
                if not chair_contact:
                    chair_contact = member.phone or ''
                if not chair_designation:
                    chair_designation = member.position_title or ''

                if member.user:
                    chair_user = member.user
                else:
                    # Look up user with same email or create user for member
                    try:
                        chair_user = User.objects.get(email=chair_email, organization=request.user.organization)
                    except User.DoesNotExist:
                        import secrets
                        chair_user = User.objects.create_user(
                            email=chair_email,
                            password=password or secrets.token_urlsafe(16),
                            organization=request.user.organization,
                            role=assigned_role,
                        )
                    member.user = chair_user
                    member.save(update_fields=['user'])

                if chair_user and chair_user.role not in ['org_admin', 'super_admin']:
                    chair_user.role = assigned_role
                    chair_user.save(update_fields=['role'])
            except Member.DoesNotExist:
                return Response({'error': 'Member not found in this organization.'}, status=status.HTTP_404_NOT_FOUND)
        elif committee_type == 'new':
            if not chair_email:
                return Response({'error': 'Email address is required.'}, status=status.HTTP_400_BAD_REQUEST)
            if not password:
                return Response({'error': 'Password is required when creating a new committee user.'}, status=status.HTTP_400_BAD_REQUEST)
            if User.objects.filter(email=chair_email).exists():
                return Response({'error': f'A user with email {chair_email} already exists.'}, status=status.HTTP_400_BAD_REQUEST)
            chair_user = User.objects.create_user(
                email=chair_email,
                password=password,
                organization=request.user.organization,
                role=assigned_role,
            )
            if not committee_name:
                committee_name = chair_email
        else:
            # Select existing user from this org by email
            if not chair_email:
                return Response({'error': 'Email is required to select existing user.'}, status=status.HTTP_400_BAD_REQUEST)
            try:
                chair_user = User.objects.get(email=chair_email, organization=request.user.organization)
                if not committee_name:
                    if hasattr(chair_user, 'memberships') and chair_user.memberships.exists():
                        committee_name = chair_user.memberships.first().full_name
                    else:
                        committee_name = chair_user.email
                if chair_user.role not in ['org_admin', 'super_admin']:
                    chair_user.role = assigned_role
                    chair_user.save(update_fields=['role'])
            except User.DoesNotExist:
                return Response({'error': 'No user with that email found in this organization.'}, status=status.HTTP_404_NOT_FOUND)

        if not committee_name:
            committee_name = chair_email or 'Election Committee Member'

        committee = ElectionCommittee.objects.create(
            election=election,
            committee_type=committee_type,
            committee_name=committee_name,
            chair_designation=chair_designation,
            chair_contact=chair_contact,
            chair_email=chair_email,
            chair_signature=chair_signature,
            include_in_letterhead=include_in_letterhead,
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
            'include_in_letterhead': include_in_letterhead,
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

        if 'include_in_letterhead' in request.data:
            val = request.data['include_in_letterhead']
            if isinstance(val, str):
                val = val.lower() in ['true', '1', 'yes']
            committee.include_in_letterhead = bool(val)

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
                if committee.chair_user.role not in ['org_admin', 'super_admin']:
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
        """
        Send a custom email to targeted recipient groups:
        - 'voters': Eligible voters in VoterRoll
        - 'candidates': Approved/submitted Candidates
        - 'election_office': Election Committee members / Officers
        """
        election = self.get_object()
        subject = request.data.get('subject')
        body_html = request.data.get('body_html')
        recipient_groups = request.data.get('recipients', ['voters'])
        
        if isinstance(recipient_groups, str):
            recipient_groups = [recipient_groups]
        
        if not subject or not body_html:
            return Response({'error': 'subject and body_html are required.'}, status=status.HTTP_400_BAD_REQUEST)
            
        from apps.voting.models import VoterRoll
        from apps.candidates.models import Candidate
        from apps.elections.models import ElectionCommittee
        from apps.notifications.tasks import send_custom_broadcast_email_task
        
        target_emails = set()

        if 'voters' in recipient_groups:
            voter_emails = VoterRoll.objects.filter(
                election=election, is_eligible=True
            ).exclude(email='').values_list('email', flat=True)
            target_emails.update([e.strip().lower() for e in voter_emails if e and e.strip()])

        if 'candidates' in recipient_groups:
            cand_emails = Candidate.objects.filter(
                election=election
            ).exclude(email='').values_list('email', flat=True)
            target_emails.update([e.strip().lower() for e in cand_emails if e and e.strip()])

        if 'election_office' in recipient_groups or 'committee' in recipient_groups:
            comm_emails = ElectionCommittee.objects.filter(
                election=election
            ).exclude(chair_email='').values_list('chair_email', flat=True)
            target_emails.update([e.strip().lower() for e in comm_emails if e and e.strip()])

        email_list = list(target_emails)
        total_count = len(email_list)

        if total_count == 0:
            return Response({'error': 'No valid recipient email addresses found for the selected group(s).'}, status=status.HTTP_400_BAD_REQUEST)

        # Dispatch Celery task with target emails and sender tracking
        send_custom_broadcast_email_task.delay(
            str(election.id),
            subject,
            body_html,
            email_list,
            sender_id=str(request.user.id),
            recipient_group=','.join(recipient_groups),
        )
        
        log_action('election.email_broadcast', request.user.organization, request.user, {
            'election_id': str(election.id),
            'queued_count': total_count,
            'recipient_groups': recipient_groups,
            'subject': subject
        })
        
        return Response({
            'message': f'Queued {total_count} email(s) for sending to {", ".join(recipient_groups)}.',
            'count': total_count,
            'recipients': recipient_groups,
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['get'], permission_classes=[IsOrgAdmin])
    def email_logs(self, request, pk=None):
        """
        List all email delivery records (successful and failed) for this election.
        """
        from apps.notifications.models import EmailBroadcastLog
        from apps.notifications.serializers import EmailBroadcastLogSerializer

        election = self.get_object()
        qs = EmailBroadcastLog.objects.filter(election=election).select_related('sender').order_by('-created_at')

        status_filter = request.query_params.get('status')
        if status_filter and status_filter.lower() != 'all':
            qs = qs.filter(status=status_filter.lower())

        search = request.query_params.get('search')
        if search and search.strip():
            from django.db.models import Q
            q_term = search.strip()
            qs = qs.filter(
                Q(recipient_email__icontains=q_term) |
                Q(subject__icontains=q_term) |
                Q(recipient_name__icontains=q_term)
            )

        serializer = EmailBroadcastLogSerializer(qs[:200], many=True)
        
        sent_count = EmailBroadcastLog.objects.filter(election=election, status='sent').count()
        failed_count = EmailBroadcastLog.objects.filter(election=election, status='failed').count()
        queued_count = EmailBroadcastLog.objects.filter(election=election, status='queued').count()

        return Response({
            'summary': {
                'total': sent_count + failed_count + queued_count,
                'sent': sent_count,
                'failed': failed_count,
                'queued': queued_count,
            },
            'logs': serializer.data,
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], permission_classes=[IsOrgAdmin])
    def retry_failed_emails(self, request, pk=None):
        """
        Retry sending any previously failed email broadcasts.
        """
        from apps.notifications.models import EmailBroadcastLog, EmailBroadcastStatus
        from apps.notifications.tasks import send_custom_broadcast_email_task

        election = self.get_object()
        failed_logs = list(EmailBroadcastLog.objects.filter(election=election, status=EmailBroadcastStatus.FAILED))
        
        if not failed_logs:
            return Response({'message': 'No failed emails found to retry.'}, status=status.HTTP_200_OK)

        retried = 0
        for log in failed_logs:
            send_custom_broadcast_email_task.delay(
                str(election.id),
                log.subject,
                log.body_html,
                [log.recipient_email],
                sender_id=str(request.user.id),
                recipient_group=log.recipient_group,
            )
            log.delete()
            retried += 1

        return Response({'message': f'Queued {retried} failed email(s) for retry.'}, status=status.HTTP_200_OK)


class ElectionNoticeViewSet(viewsets.ModelViewSet):
    """
    Manage notices for an election.
    """
    serializer_class = ElectionNoticeSerializer
    
    def get_permissions(self):
        if self.action == 'print_letterhead':
            return [permissions.AllowAny()]
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [IsElectionOfficer()]
        return [IsObserver()]

    def get_queryset(self):
        qs = ElectionNotice.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )
        if not (self.request.user.is_org_admin or self.request.user.is_superuser):
            from apps.elections.models import ElectionRoleAssignment
            is_officer = ElectionRoleAssignment.objects.filter(
                user=self.request.user,
                election_id=self.kwargs['election_pk'],
                role='election_officer'
            ).exists()
            if not is_officer:
                qs = qs.filter(is_published=True)
        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )
        serializer.save(election=election)

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny])
    def print_letterhead(self, request, election_pk=None, pk=None):
        from django.shortcuts import get_object_or_404
        from django.http import HttpResponse

        notice = get_object_or_404(ElectionNotice, pk=pk, election_id=election_pk)
        election = notice.election
        org = election.organization if election else None

        serializer = ElectionNoticeSerializer(notice, context={'request': request})
        data = serializer.data

        org_name = data.get('org_name') or (org.name if org else 'Nepal Association / संस्था')
        org_address = data.get('org_address') or (org.address if org else 'Kathmandu, Nepal')
        org_phone = data.get('org_phone') or (org.phone if org else '+977-1-4XXXXXX')
        org_email = data.get('org_email') or (org.email if org else 'election@org.np')
        org_logo = data.get('org_logo_url') or ''
        election_year = data.get('election_year') or '2083'
        notice_number = data.get('notice_number') or f'{election_year}/01'
        stamp_mode = request.GET.get('stamp_mode') or notice.stamp_mode or (election.stamp_mode if election else 'digital') or 'digital'
        stamp_image = data.get('election_stamp_image') or ''
        signatories = data.get('signatories') or []

        # Format Nepali date
        nepali_date = ''
        english_date = ''
        if notice.created_at:
            try:
                import nepali_datetime
                ndt = nepali_datetime.date.from_datetime_date(notice.created_at.date())
                nepali_date = f"{ndt.year}/{ndt.month:02d}/{ndt.day:02d} ({ndt.strftime('%K %N')})"
                english_date = notice.created_at.strftime('%B %d, %Y')
            except Exception:
                nepali_date = str(notice.created_at.date())
                english_date = notice.created_at.strftime('%B %d, %Y')

        # Signatories HTML
        signatories_html = ""
        for s in signatories:
            name = s.get('name') or 'Election Officer'
            desig = s.get('designation') or 'Committee Member'
            sig_url = s.get('signature_url') or ''

            sig_content = f'<img src="{sig_url}" class="sig-img" alt="Signature">' if sig_url else '<div style="height:40px;"></div>'
            signatories_html += f"""
            <div class="signatory-card">
              {sig_content}
              <div class="sig-line"></div>
              <div class="sig-name">( {name} )</div>
              <div class="sig-desig">{desig}</div>
              <div class="sig-comm">निर्वाचन समिति</div>
            </div>
            """

        committee_members = data.get('committee_members') or []
        if not committee_members and election:
            for c in election.committees.all():
                full_name = ''
                if c.chair_user and hasattr(c.chair_user, 'memberships') and c.chair_user.memberships.exists():
                    full_name = c.chair_user.memberships.first().full_name
                elif c.committee_name:
                    full_name = c.committee_name
                else:
                    full_name = c.chair_email
                committee_members.append({
                    'name': full_name,
                    'designation': c.chair_designation or 'Election Officer',
                    'role': c.role,
                })

        # Build Left Committee Roster Sidebar HTML
        tenure_range = f"({election_year}-{int(election_year)+3})" if election_year.isdigit() else f"({election_year})"
        committee_sidebar_html = ""
        for m in committee_members:
            m_name = m.get('name') or 'Election Officer'
            m_desig = m.get('designation') or 'Election Officer'
            committee_sidebar_html += f"""
            <div style="margin-bottom: 20px;">
              <div style="font-weight: bold; font-size: 11.5px; color: #0F172A; line-height: 1.3;">{m_desig}:</div>
              <div style="font-size: 11.5px; color: #334155; margin-top: 2px;">{m_name}</div>
            </div>
            """

        digital_seal_html = f'<img src="{stamp_image}" style="width:100px; height:100px; border-radius:50%; border:2px solid #DC2626; object-fit:contain;" alt="Official Stamp">' if stamp_image else '''
        <div class="stamp-digital">
          <div>★ निर्वाचन समिति ★</div>
          <div style="font-size:16px; margin:2px 0;">🛡️</div>
          <div>आधिकारिक छाप</div>
          <div style="font-size:7px;">OFFICIAL SEAL</div>
        </div>
        '''

        manual_seal_html = '''
        <div class="stamp-manual">
          <div>[ आधिकारिक छाप ]</div>
          <div style="font-size:7.5px;">OFFICIAL SEAL</div>
          <div style="font-size:7px; color:#94A3B8;">(स्थान)</div>
        </div>
        '''

        if stamp_mode == 'both':
            stamp_html = f'''
            <div style="display: flex; align-items: center; gap: 10px;">
              {digital_seal_html}
              {manual_seal_html}
            </div>
            '''
        elif stamp_mode == 'manual':
            stamp_html = manual_seal_html
        else:
            stamp_html = digital_seal_html

        notice_content = (notice.content or '').replace('\n', '<br>')
        logo_html = f'<img src="{org_logo}" class="header-logo" alt="Logo">' if org_logo else '<div class="header-logo" style="background:#EEF2FF; border:1px solid #C7D2FE; display:flex; align-items:center; justify-content:center; font-size:28px;">🏛️</div>'

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>{notice.title} - Official Election Notice Letterhead</title>
  <style>
    @page {{
      size: A4 portrait;
      margin: 12mm 12mm 12mm 12mm;
    }}
    @media print {{
      body {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
      .no-print {{ display: none !important; }}
    }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, BlinkMacSystemFont, Arial, sans-serif;
      color: #1E293B;
      background: #F8FAFC;
      margin: 0;
      padding: 20px;
    }}
    .action-bar {{
      max-width: 820px;
      margin: 0 auto 16px auto;
      display: flex;
      justify-content: flex-end;
      gap: 12px;
    }}
    .btn {{
      background: #4F46E5;
      color: white;
      border: none;
      padding: 8px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      font-size: 13px;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }}
    .btn:hover {{ background: #4338CA; }}
    .letterhead {{
      max-width: 820px;
      margin: 0 auto;
      background: #FFFFFF;
      padding: 32px 36px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.08);
      border: 1px solid #CBD5E1;
      position: relative;
    }}
    .header-table {{
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 6px;
    }}
    .header-logo {{
      width: 85px;
      height: 85px;
      object-fit: contain;
      border-radius: 50%;
    }}
    .org-title-ne {{
      font-size: 20px;
      font-weight: 900;
      color: #0F172A;
      text-align: center;
      margin: 0 0 2px 0;
    }}
    .org-title-en {{
      font-size: 14px;
      font-weight: 800;
      color: #1E293B;
      text-align: center;
      letter-spacing: 0.4px;
      text-transform: uppercase;
      margin: 0 0 2px 0;
    }}
    .committee-title {{
      font-size: 13.5px;
      font-weight: bold;
      color: #0F172A;
      text-align: center;
      letter-spacing: 0.2px;
      margin: 0 0 2px 0;
    }}
    .tenure-sub {{
      font-size: 12px;
      font-weight: bold;
      color: #334155;
      text-align: center;
      margin: 0 0 4px 0;
    }}
    .org-meta {{
      font-size: 10px;
      color: #475569;
      text-align: center;
      line-height: 1.4;
      margin: 2px 0;
    }}
    .divider-solid {{
      height: 1.5px;
      background: #0F172A;
      width: 100%;
      margin-top: 10px;
    }}
    .main-grid {{
      display: grid;
      grid-template-columns: 215px 1fr;
      margin-top: 12px;
      min-height: 580px;
    }}
    .left-sidebar {{
      border-right: 1.5px solid #0F172A;
      padding-right: 16px;
      padding-top: 8px;
    }}
    .right-content {{
      padding-left: 24px;
      padding-top: 8px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }}
    .date-text {{
      text-align: right;
      font-weight: bold;
      font-size: 12px;
      color: #0F172A;
      margin-bottom: 12px;
    }}
    .notice-title-box {{
      text-align: center;
      font-size: 18px;
      font-weight: 900;
      color: #0F172A;
      margin: 10px 0 16px 0;
      letter-spacing: 0.5px;
    }}
    .content-body {{
      font-size: 13px;
      line-height: 1.85;
      text-align: justify;
      color: #1E293B;
    }}
    .stamp-digital {{
      width: 95px;
      height: 95px;
      border: 2px solid #DC2626;
      border-radius: 50%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #DC2626;
      text-align: center;
      font-size: 8px;
      font-weight: bold;
    }}
    .stamp-manual {{
      width: 95px;
      height: 95px;
      border: 1.5px dashed #94A3B8;
      border-radius: 50%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #64748B;
      text-align: center;
      font-size: 8px;
    }}
    .signatories-block {{
      display: flex;
      flex-wrap: wrap;
      gap: 20px;
      justify-content: flex-end;
    }}
    .signatory-card {{
      text-align: center;
      width: 140px;
    }}
    .sig-img {{
      height: 46px;
      max-width: 130px;
      object-fit: contain;
      margin-bottom: 2px;
    }}
    .sig-line {{
      width: 140px;
      border-bottom: 1.2px solid #1E293B;
      margin: 0 auto 3px auto;
    }}
    .sig-name {{
      font-weight: bold;
      font-size: 11.5px;
      color: #0F172A;
    }}
    .sig-desig {{
      font-size: 10.5px;
      font-weight: 600;
      color: #334155;
    }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <button class="btn" onclick="window.print()">🖨️ Print / Save as PDF</button>
  </div>
  <div class="letterhead">
    <!-- Header Section -->
    <table class="header-table">
      <tr>
        <td style="width: 90px; vertical-align: top;">
          {logo_html}
        </td>
        <td style="text-align: center; padding: 0 10px; vertical-align: top;">
          <div class="org-title-ne">{org_name}</div>
          <div class="org-title-en">{org.name if org else 'NEPAL MEDICAL ASSOCIATION'}</div>
          <div class="committee-title">ELECTION COMMITTEE</div>
          <div class="tenure-sub">{tenure_range}</div>
          <div class="org-meta">
            {org_address}. Telephone no. {org_phone}. Email: {org_email}
          </div>
        </td>
        <td style="width: 130px; text-align: right; vertical-align: top; font-size: 10px; font-weight: bold; color: #334155; line-height: 1.4;">
          <div>Regd. No. {notice_number}</div>
        </td>
      </tr>
    </table>

    <!-- Overlapping Stamp Seal -->
    <div style="position: absolute; right: 260px; top: 75px; z-index: 10;">
      {stamp_html}
    </div>

    <!-- Solid Divider Line -->
    <div class="divider-solid"></div>

    <!-- 2-Column Statutory Body Layout -->
    <div class="main-grid">
      <!-- Left Column: Election Committee Roster -->
      <div class="left-sidebar">
        <div style="font-weight: 900; font-size: 11.5px; color: #0F172A; text-transform: uppercase; margin-bottom: 2px;">
          ELECTION COMMITTEE
        </div>
        <div style="font-weight: bold; font-size: 11px; color: #334155; margin-bottom: 16px;">
          {tenure_range}
        </div>

        {committee_sidebar_html}
      </div>

      <!-- Right Column: Notice Body -->
      <div class="right-content">
        <div>
          <!-- Date -->
          <div class="date-text">
            मिति: {nepali_date}
          </div>

          <!-- Notice Header -->
          <div class="notice-title-box">
            सूचना !
          </div>

          {f'<div style="font-weight:bold; font-size:13px; margin-bottom:14px; text-align:center;">विषय: {notice.title}</div>' if notice.title != 'सूचना' and notice.title != 'सूचना !' else ''}

          <!-- Notice Body Paragraphs -->
          <div class="content-body">
            {notice_content}
          </div>
        </div>

        <!-- Bottom Signatories -->
        <div style="margin-top: 36px; display: flex; justify-content: flex-end;">
          <div class="signatories-block">
            {signatories_html}
          </div>
        </div>
      </div>
    </div>
  </div>

  <script>
    window.onload = function() {{
      setTimeout(function() {{
        window.print();
      }}, 500);
    }};
  </script>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html; charset=utf-8')


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

    def destroy(self, request, *args, **kwargs):
        instance = self.get_object()
        self.check_object_permissions(request, instance.election)
        if instance.candidates.exists():
            return Response(
                {
                    'error': {
                        'code': 'HAS_CANDIDATES',
                        'message': f"Cannot delete designation '{instance.title}' because {instance.candidates.count()} candidate(s) are already registered under it. Please remove or reassign candidates first.",
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        return super().destroy(request, *args, **kwargs)


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

