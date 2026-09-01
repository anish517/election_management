from django.db.models import Q
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
            'create_committee', 'assignments',
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
        user = self.request.user
        if not user or not user.is_authenticated or not user.organization:
            return Election.objects.none()

        # Auto advance any due election milestones for this organization
        _advance_due_elections(user.organization)
        base_qs = Election.objects.filter(organization=user.organization)

        # Administrative roles can view all elections in their organization
        admin_roles = {'org_admin', 'election_officer', 'observer', 'auditor', 'super_admin'}
        user_role = getattr(user, 'role', '')
        if user_role in admin_roles or user.is_staff or user.is_superuser:
            return base_qs

        # For Voters & Candidates: Scope strictly to elections they are enrolled in
        user_email = user.email.strip().lower() if user.email else ''
        user_phone = getattr(user, 'phone', '').strip() if hasattr(user, 'phone') else ''

        voter_filter = Q()
        if user_email:
            voter_filter |= Q(voter_roll__email__iexact=user_email, voter_roll__is_eligible=True)
            voter_filter |= Q(candidates__email__iexact=user_email)
        if user_phone:
            voter_filter |= Q(voter_roll__phone=user_phone, voter_roll__is_eligible=True)

        if not voter_filter:
            return Election.objects.none()

        return base_qs.filter(voter_filter).distinct()

    def perform_create(self, serializer):
        org = self.request.user.organization
        kwargs = {
            'organization': org,
            'created_by': self.request.user,
        }
        if 'results_visibility' not in serializer.validated_data and org and getattr(org, 'default_result_visibility', None):
            kwargs['results_visibility'] = org.default_result_visibility

        election = serializer.save(**kwargs)
        if election.election_type == 'samanupatik' and not election.positions.exists():
            Position.objects.create(
                election=election,
                title="Samānupātik PR Representative (समानुपातिक प्रतिनिधि)",
                seats_available=election.total_pr_seats or 10,
                voting_method='samanupatik',
                max_votes_per_voter=1,
                result_order=1,
            )
        log_action('election.created', self.request.user.organization, self.request.user, {
            'election_id': str(election.id),
            'title': election.title
        })

    def perform_update(self, serializer):
        election = serializer.save()
        if election.election_type == 'samanupatik' and not election.positions.exists():
            Position.objects.create(
                election=election,
                title="Samānupātik PR Representative (समानुपातिक प्रतिनिधि)",
                seats_available=election.total_pr_seats or 10,
                voting_method='samanupatik',
                max_votes_per_voter=1,
                result_order=1,
            )
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
                nepali_date = f"{ndt.year}/{ndt.month:02d}/{ndt.day:02d}"
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

        # Detect if notice is results declaration notice
        t_low = (notice.title or '').lower()
        c_low = (notice.content or '').lower()
        is_results_notice = any(k in t_low or k in c_low for k in ['मतदान सम्पन्न', 'मत परिणाम', 'परिणाम', 'voting completed', 'result'])

        # Build Left Committee Roster Sidebar HTML
        tenure_range = f"({election_year}-{int(election_year)+3})" if election_year.isdigit() else f"({election_year})"
        committee_sidebar_html = ""
        for m in committee_members:
            m_name = m.get('name') or 'Election Officer'
            m_desig = m.get('designation') or 'Election Officer'
            committee_sidebar_html += f"""
            <div style="margin-bottom: 8px;">
              <div style="font-weight: bold; font-size: 10px; color: #0F172A; line-height: 1.2;">{m_desig}:</div>
              <div style="font-size: 9.5px; color: #334155; margin-top: 1px;">{m_name}</div>
            </div>
            """

        digital_seal_html = f'<img src="{stamp_image}" style="width:72px; height:72px; border-radius:50%; border:1.5px solid #DC2626; object-fit:contain;" alt="Official Stamp">' if stamp_image else '''
        <div class="stamp-digital">
          <div>★ निर्वाचन समिति ★</div>
          <div style="font-size:12px; margin:1px 0;">🛡️</div>
          <div>आधिकारिक छाप</div>
          <div style="font-size:6px;">OFFICIAL SEAL</div>
        </div>
        '''

        manual_seal_html = '''
        <div class="stamp-manual">
          <div>[ आधिकारिक छाप ]</div>
          <div style="font-size:6.5px;">OFFICIAL SEAL</div>
          <div style="font-size:6px; color:#94A3B8;">(स्थान)</div>
        </div>
        '''

        if stamp_mode == 'both':
            stamp_html = f'''
            <div style="display: flex; align-items: center; gap: 6px;">
              {digital_seal_html}
              {manual_seal_html}
            </div>
            '''
        elif stamp_mode == 'manual':
            stamp_html = manual_seal_html
        else:
            stamp_html = digital_seal_html

        def render_markdown_table(t_lines):
            if len(t_lines) < 2:
                return ''
            raw_headers = [c.strip() for c in t_lines[0].split('|') if c.strip()]
            is_5_col = len(raw_headers) == 5

            if is_5_col:
                headers = [raw_headers[0], raw_headers[1], raw_headers[2], 'प्राप्त मत तथा नतिजा (Votes & Status)']
            else:
                headers = raw_headers

            th_cells = ''.join([f'<th style="background:#F1F5F9; font-weight:bold; font-size:11px; padding:6px 8px; border:1px solid #CBD5E1; color:#0F172A; text-align:center;">{h}</th>' for h in headers])
            rows_html = ''
            for l in t_lines[1:]:
                clean = l.replace('-', '').replace(':', '').replace('|', '').strip()
                if not clean:
                    continue
                raw_cells = [c.strip() for c in l.split('|') if c.strip()]
                if is_5_col and len(raw_cells) == 5:
                    votes = raw_cells[3]
                    status = raw_cells[4]
                    if status and status != '-':
                        combined_status = f"{votes} &nbsp; <b>{status}</b>"
                    else:
                        combined_status = votes
                    cells = [raw_cells[0], raw_cells[1], raw_cells[2], combined_status]
                else:
                    cells = raw_cells

                is_win = '🏆 ELECTED' in l or 'विजयी' in l or 'UNCONTESTED' in l or 'निर्विरोध' in l
                is_tie = '⚠️ TIED' in l or 'बराबरी' in l
                bg_style = 'background:#ECFDF5;' if is_win else ('background:#FFFBEB;' if is_tie else '')
                tds = ''
                for idx, c in enumerate(cells):
                    is_last_col = (idx == len(cells) - 1)
                    color = '#059669' if is_win and is_last_col else ('#B45309' if is_tie and is_last_col else '#1E293B')
                    weight = 'bold' if is_win or is_tie or idx == 0 else 'normal'
                    tds += f'<td style="padding:5px 8px; border:1px solid #E2E8F0; font-size:10.5px; font-weight:{weight}; color:{color}; line-height:1.35; text-align:center;">{c}</td>'
                rows_html += f'<tr style="{bg_style}">{tds}</tr>'
            return f'<table style="width:100%; border-collapse:collapse; margin:10px auto; border:1px solid #CBD5E1; text-align:center;"><thead><tr>{th_cells}</tr></thead><tbody>{rows_html}</tbody></table>'

        def format_notice_content_html(raw_content):
            if not raw_content:
                return ''
            if '|' in raw_content and '---' in raw_content:
                lines = raw_content.split('\n')
                out = []
                table_lines = []
                in_table = False
                for line in lines:
                    trimmed = line.strip()
                    if trimmed.startswith('|') and trimmed.endswith('|'):
                        in_table = True
                        table_lines.append(trimmed)
                    else:
                        if in_table and table_lines:
                            out.append(render_markdown_table(table_lines))
                            table_lines = []
                            in_table = False
                        if trimmed:
                            out.append(f'<p style="margin: 0 0 8px 0; line-height: 1.6; font-size: 12px; text-align: center;">{trimmed}</p>')
                if in_table and table_lines:
                    out.append(render_markdown_table(table_lines))
                return ''.join(out)
            return f'<div style="text-align: center; line-height: 1.6; font-size: 12px;">{raw_content.replace(chr(10), "<br>")}</div>'

        notice_content = format_notice_content_html(notice.content or '')
        logo_html = f'<img src="{org_logo}" class="header-logo" alt="Logo">' if org_logo else '<div class="header-logo" style="background:#EEF2FF; border:1px solid #C7D2FE; display:flex; align-items:center; justify-content:center; font-size:24px;">🏛️</div>'

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>{notice.title} - Official Election Notice Letterhead</title>
  <style>
    @page {{
      size: A4 portrait;
      margin: 8mm 10mm 12mm 10mm;
    }}
    @media print {{
      body {{
        margin: 0 !important;
        padding: 0 !important;
        background: none !important;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
      }}
      .no-print {{ display: none !important; }}
      .letterhead {{
        box-shadow: none !important;
        border: none !important;
        padding: 0 !important;
        margin: 0 !important;
        max-width: 100% !important;
      }}
      .doc-print-table {{
        width: 100% !important;
        border-collapse: collapse !important;
        border: none !important;
      }}
      .doc-print-table tfoot {{
        display: table-footer-group !important;
      }}
      .signatories-block-repeating {{
        page-break-inside: avoid !important;
      }}
      table {{
        page-break-inside: auto;
      }}
      thead {{
        display: table-header-group;
      }}
      tr {{
        page-break-inside: avoid;
        page-break-after: auto;
      }}
      tbody {{
        display: table-row-group;
      }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, BlinkMacSystemFont, Arial, sans-serif;
      color: #1E293B;
      background: #F8FAFC;
      margin: 0;
      padding: 16px;
    }}
    .action-bar {{
      max-width: 840px;
      margin: 0 auto 12px auto;
      display: flex;
      justify-content: flex-end;
      gap: 10px;
    }}
    .btn {{
      background: #4F46E5;
      color: white;
      border: none;
      padding: 7px 16px;
      border-radius: 6px;
      font-weight: 600;
      cursor: pointer;
      font-size: 12.5px;
      display: inline-flex;
      align-items: center;
      gap: 6px;
    }}
    .btn:hover {{ background: #4338CA; }}
    .letterhead {{
      max-width: 840px;
      margin: 0 auto;
      background: #FFFFFF;
      padding: 20px 24px;
      box-shadow: 0 4px 16px rgba(0,0,0,0.06);
      border: 1px solid #CBD5E1;
      position: relative;
    }}
    .header-table {{
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 4px;
    }}
    .header-logo {{
      width: 68px;
      height: 68px;
      object-fit: contain;
      border-radius: 50%;
    }}
    .org-title-ne {{
      font-size: 18px;
      font-weight: 900;
      color: #0F172A;
      text-align: center;
      margin: 0 0 1px 0;
      line-height: 1.2;
    }}
    .org-title-en {{
      font-size: 12.5px;
      font-weight: 800;
      color: #1E293B;
      text-align: center;
      letter-spacing: 0.3px;
      text-transform: uppercase;
      margin: 0 0 1px 0;
    }}
    .committee-title {{
      font-size: 11.5px;
      font-weight: 900;
      color: #4F46E5;
      text-align: center;
      letter-spacing: 0.3px;
      margin: 0 0 1px 0;
    }}
    .tenure-sub {{
      font-size: 10.5px;
      font-weight: 800;
      color: #4F46E5;
      text-align: center;
      margin: 0 0 2px 0;
    }}
    .org-meta {{
      font-size: 9px;
      color: #475569;
      text-align: center;
      line-height: 1.3;
      margin: 1px 0;
    }}
    .divider-solid {{
      height: 1.5px;
      background: #0F172A;
      width: 100%;
      margin-top: 6px;
    }}
    .main-grid {{
      display: grid;
      grid-template-columns: 170px 1fr;
      margin-top: 8px;
    }}
    .left-sidebar {{
      border-right: 1.2px solid #0F172A;
      padding-right: 12px;
      padding-top: 6px;
    }}
    .right-content {{
      padding-left: 16px;
      padding-top: 6px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
    }}
    .date-text {{
      text-align: right;
      font-weight: bold;
      font-size: 11px;
      color: #0F172A;
    }}
    .notice-title-box {{
      text-align: center;
      font-size: 17px;
      font-weight: 900;
      color: #0F172A;
      margin: 0 0 4px 0;
      letter-spacing: 0.4px;
    }}
    .content-body {{
      font-size: 12px;
      line-height: 1.6;
      text-align: center;
      color: #1E293B;
    }}
    .stamp-digital {{
      width: 76px;
      height: 76px;
      border: 1.5px solid #DC2626;
      border-radius: 50%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #DC2626;
      text-align: center;
      font-size: 7px;
      font-weight: bold;
      line-height: 1.1;
    }}
    .stamp-manual {{
      width: 76px;
      height: 76px;
      border: 1.2px dashed #94A3B8;
      border-radius: 50%;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: #64748B;
      text-align: center;
      font-size: 7px;
    }}
    .signatories-block {{
      display: flex;
      flex-wrap: wrap;
      gap: 16px;
      justify-content: center;
    }}
    .signatory-card {{
      text-align: center;
      width: 130px;
    }}
    .sig-img {{
      height: 36px;
      max-width: 120px;
      object-fit: contain;
      margin-bottom: 2px;
    }}
    .sig-line {{
      width: 130px;
      border-bottom: 1px solid #1E293B;
      margin: 0 auto 3px auto;
    }}
    .sig-name {{
      font-weight: bold;
      font-size: 11px;
      color: #0F172A;
    }}
    .sig-desig {{
      font-size: 9.5px;
      font-weight: 600;
      color: #334155;
    }}
    .sig-comm {{
      font-size: 8.5px;
      color: #64748B;
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
        <td style="width: 76px; vertical-align: top;">
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
        <td style="width: 120px; text-align: right; vertical-align: top; font-size: 10px; font-weight: bold; color: #334155; line-height: 1.35;">
          <div>Regd. No. {notice_number}</div>
        </td>
      </tr>
    </table>

    <!-- Solid Divider Line -->
    <div class="divider-solid"></div>

    <!-- Document Print Wrapper Table (repeats tfoot on every printed page) -->
    <table class="doc-print-table" style="width: 100%; border-collapse: collapse; border: none;">
      <tbody>
        <tr>
          <td style="border: none; padding: 0; vertical-align: top;">
            <!-- 2-Column Statutory Body Layout -->
            <div class="main-grid">
              <!-- Left Column: Election Committee Roster -->
              <div class="left-sidebar">
                <div style="font-weight: 900; font-size: 11px; color: #4F46E5; text-transform: uppercase; margin-bottom: 2px; letter-spacing: 0.2px;">
                  ELECTION COMMITTEE
                </div>
                <div style="font-weight: 800; font-size: 10.5px; color: #4F46E5; margin-bottom: 12px;">
                  {tenure_range}
                </div>

                {committee_sidebar_html}
              </div>

              <!-- Right Column: Notice Body -->
              <div class="right-content">
                <div>
                  <!-- Notice Sub-Header: Left Stamp + Center Title/Subject + Right Date -->
                  <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; gap: 12px;">
                    <!-- LEFT: Official Stamp -->
                    <div style="flex-shrink: 0; display: flex; justify-content: flex-start;">
                      {stamp_html}
                    </div>

                    <!-- CENTER: Notice Title & Subject -->
                    <div style="flex: 1; text-align: center;">
                      <div class="notice-title-box">
                        सूचना !
                      </div>
                      {f'<div style="font-weight:bold; font-size:13px; text-align:center; margin: 4px 0 2px 0; color:#0F172A;">विषय: {notice.title}</div>' if notice.title != 'सूचना' and notice.title != 'सूचना !' else ''}
                    </div>

                    <!-- RIGHT: Date -->
                    <div style="flex-shrink: 0; text-align: right; min-width: 80px;">
                      <div class="date-text">
                        मिति: {nepali_date}
                      </div>
                    </div>
                  </div>

                  <!-- Notice Body Paragraphs (Center-Aligned) -->
                  <div class="content-body">
                    {notice_content}
                  </div>
                </div>

                <!-- On-Screen Signatories Block -->
                <div style="margin-top: 24px; display: flex; justify-content: center;">
                  <div class="signatories-block">
                    {signatories_html}
                  </div>
                </div>
              </div>
            </div>
          </td>
        </tr>
      </tbody>

      <!-- Multi-Page Print Repeating Footer (repeats signatures at the bottom of every printed page) -->
      <tfoot class="print-repeating-footer no-screen" style="border-top: 1px solid #CBD5E1;">
        <tr>
          <td style="border: none; padding-top: 12px; padding-bottom: 4px;">
            <div style="display: flex; justify-content: space-between; align-items: flex-end; border-top: 1px solid #E2E8F0; padding-top: 8px;">
              <div style="font-size: 9px; color: #64748B; font-style: italic;">
                {org_name} • निर्वाचन समिति • {notice.title}
              </div>
              <div class="signatories-block-repeating" style="display: flex; gap: 14px; justify-content: flex-end;">
                {signatories_html}
              </div>
            </div>
          </td>
        </tr>
      </tfoot>
    </table>
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

