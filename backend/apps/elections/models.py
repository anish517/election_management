"""
Election, Position, ElectionStateTransition, ElectionRoleAssignment Models
(doc: 08-Database-Design.md §8.2 elections, positions tables)
(doc: 13-Election-Management.md)
(doc: 07-System-Architecture.md §7.5 Election State Machine)
"""
from django.db import models
from django.utils import timezone
from apps.core.models import TimestampedModel, UUIDModel


class ElectionState(models.TextChoices):
    DRAFT = 'draft', 'Draft'
    PUBLISHED = 'published', 'Published'
    NOMINATION_OPEN = 'nomination_open', 'Nomination Open'
    NOMINATION_CLOSED = 'nomination_closed', 'Nomination Closed'
    VOTING_OPEN = 'voting_open', 'Voting Open'
    VOTING_CLOSED = 'voting_closed', 'Voting Closed'
    RESULTS_PROVISIONAL = 'results_provisional', 'Results Provisional'
    RESULTS_FINAL = 'results_final', 'Results Final'
    CANCELLED = 'cancelled', 'Cancelled'


class VotingMethod(models.TextChoices):
    FPTP = 'fptp', 'First-Past-The-Post'
    MULTI_CHOICE = 'multi_choice', 'Multiple Choice (Block)'
    RANKED_CHOICE = 'ranked_choice', 'Ranked Choice (STV)'
    APPROVAL = 'approval', 'Approval Voting'
    WEIGHTED = 'weighted', 'Weighted Voting'
    PROXY = 'proxy', 'Proxy Voting'
    YES_NO = 'yes_no', 'Yes/No (Referendum)'


class ResultsVisibility(models.TextChoices):
    ADMIN_ONLY = 'admin_only', 'Admin Only'
    ORG_MEMBERS = 'org_members', 'Organization Members'
    PUBLIC = 'public', 'Public'


class Election(TimestampedModel):
    """
    Central election entity — the main workflow object.
    (doc: 08-Database-Design.md §8.2 elections table)
    (doc: 07-System-Architecture.md §7.5 — state machine)
    """
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        related_name='elections',
        db_index=True,
    )
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True, default='')

    # Identity / Branding
    prefix = models.CharField(max_length=20, blank=True, default='')
    logo_url = models.URLField(blank=True, default='')
    contact_number = models.CharField(max_length=30, blank=True, default='')
    primary_color = models.CharField(max_length=7, blank=True, default='#6C5CE7')
    secondary_color = models.CharField(max_length=7, blank=True, default='#A29BFE')
    
    # Guidelines
    guidelines = models.TextField(blank=True, default='')

    # State machine (doc: 07-System-Architecture.md §7.5)
    state = models.CharField(
        max_length=30, choices=ElectionState.choices,
        default=ElectionState.DRAFT, db_index=True,
    )

    # Voter roll freeze (doc: 12-Member-Management.md §12.3, doc: 03-Nepal-Election-Workflow.md §3.2)
    voter_roll_freeze_date = models.DateField(null=True, blank=True)
    voter_roll_frozen_at = models.DateTimeField(null=True, blank=True)

    # Voter List Schedule
    first_voter_list_date = models.DateTimeField(null=True, blank=True)
    voter_list_claim_date = models.DateTimeField(null=True, blank=True)
    final_voter_list_date = models.DateTimeField(null=True, blank=True)

    # Nepal-specific election schedule (doc: 03-Nepal-Election-Workflow.md §3.2)
    nomination_open_at = models.DateTimeField(null=True, blank=True)
    nomination_close_at = models.DateTimeField(null=True, blank=True)
    candidacy_claim_date = models.DateTimeField(null=True, blank=True)
    candidacy_final_date = models.DateTimeField(null=True, blank=True)
    withdrawal_deadline = models.DateTimeField(null=True, blank=True)
    campaign_silent_from = models.DateTimeField(null=True, blank=True)
    voting_start_at = models.DateTimeField(null=True, blank=True)
    voting_end_at = models.DateTimeField(null=True, blank=True)

    # Grievance window (doc: 03-Nepal-Election-Workflow.md §3.2)
    result_contest_deadline = models.DateTimeField(null=True, blank=True)

    # Nominee / Candidacy payment
    is_paid_candidacy = models.BooleanField(default=False)
    nominee_charge = models.DecimalField(max_digits=10, decimal_places=2, default=0)

    # Ballot & results settings
    is_secret_ballot = models.BooleanField(default=True)
    allow_boycott = models.BooleanField(
        default=True,
        help_text='Allow voters to choose No Vote / Boycott (बहिष्कार)'
    )
    results_visibility = models.CharField(
        max_length=20, choices=ResultsVisibility.choices,
        default=ResultsVisibility.ADMIN_ONLY,
    )
    live_turnout_enabled = models.BooleanField(default=True)
    resubmission_allowed = models.BooleanField(
        default=False,
        help_text='Allow rejected candidates to resubmit (doc: 14-Candidate-Management.md §14.3)'
    )
    ballot_snapshot_hash = models.CharField(
        max_length=64, blank=True, default='',
        help_text='SHA-256 of locked candidate list at voting-open time (doc: 16-Ballot-Builder.md §16.7)'
    )

    created_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL,
        null=True, related_name='elections_created'
    )
    cancellation_reason = models.TextField(blank=True, default='')


    class Meta:
        db_table = 'elections'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.title} [{self.state}] — {self.organization.name}"

    # ------------------------------------------------------------------
    # State machine helpers (doc: 07-System-Architecture.md §7.5)
    # ------------------------------------------------------------------
    VALID_TRANSITIONS = {
        ElectionState.DRAFT: [ElectionState.PUBLISHED, ElectionState.CANCELLED],
        ElectionState.PUBLISHED: [ElectionState.NOMINATION_OPEN, ElectionState.CANCELLED],
        ElectionState.NOMINATION_OPEN: [ElectionState.NOMINATION_CLOSED, ElectionState.CANCELLED],
        ElectionState.NOMINATION_CLOSED: [ElectionState.VOTING_OPEN, ElectionState.CANCELLED],
        ElectionState.VOTING_OPEN: [ElectionState.VOTING_CLOSED],
        ElectionState.VOTING_CLOSED: [ElectionState.RESULTS_PROVISIONAL, ElectionState.RESULTS_FINAL],
        ElectionState.RESULTS_PROVISIONAL: [ElectionState.RESULTS_FINAL],
        ElectionState.RESULTS_FINAL: [],
        ElectionState.CANCELLED: [],
    }

    def can_transition_to(self, new_state):
        return new_state in self.VALID_TRANSITIONS.get(self.state, [])

    def transition_to(self, new_state, triggered_by=None):
        """
        Perform a state transition, recording it in ElectionStateTransition.
        (doc: 07-System-Architecture.md §7.5)
        """
        if not self.can_transition_to(new_state):
            raise ValueError(
                f"Cannot transition from {self.state!r} to {new_state!r}"
            )
        old_state = self.state
        self.state = new_state
        self.save(update_fields=['state', 'updated_at'])

        ElectionStateTransition.objects.create(
            election=self,
            from_state=old_state,
            to_state=new_state,
            triggered_by=triggered_by,
        )
        return self


class ElectionStateTransition(UUIDModel):
    """
    Audit trail for every election state change.
    Every transition is a new row — free timeline/history.
    (doc: 07-System-Architecture.md §7.5)
    """
    election = models.ForeignKey(
        Election, on_delete=models.CASCADE, related_name='state_transitions'
    )
    from_state = models.CharField(max_length=30, choices=ElectionState.choices)
    to_state = models.CharField(max_length=30, choices=ElectionState.choices)
    triggered_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True, blank=True,
        help_text='Null = system-triggered (Celery)'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'election_state_transitions'
        ordering = ['created_at']


class Position(TimestampedModel):
    """
    A position within an election (e.g., President, Board Member).
    (doc: 08-Database-Design.md §8.2 positions table)
    """
    election = models.ForeignKey(
        Election, on_delete=models.CASCADE, related_name='positions'
    )
    title = models.CharField(max_length=255)
    seats_available = models.PositiveIntegerField(default=1)
    voting_method = models.CharField(
        max_length=20, choices=VotingMethod.choices, default=VotingMethod.FPTP
    )
    # UI and Results Ordering
    quota_name = models.CharField(max_length=100, blank=True, default='', help_text='e.g., Dalit, Female, Open')
    bg_color = models.CharField(max_length=7, blank=True, default='#563d7c')
    result_order = models.IntegerField(default=0, help_text='Lower numbers appear first in results')
    nominee_charge = models.DecimalField(max_digits=10, decimal_places=2, default=0.00)

    max_votes_per_voter = models.PositiveIntegerField(
        default=1,
        help_text='Relevant for multi_choice — how many candidates voter can pick'
    )
    # Flexible JSON eligibility rule (doc: 12-Member-Management.md §12.6)
    eligibility_rule = models.JSONField(
        default=dict, blank=True,
        help_text='e.g. {"membership_status": "active", "min_membership_months": 12}'
    )
    # Ballot ordering (doc: 14-Candidate-Management.md §14.7)
    ballot_ordering = models.CharField(
        max_length=20,
        choices=[('alphabetical', 'Alphabetical'), ('random', 'Random'), ('manual', 'Manual')],
        default='random',
    )
    # Yes/No referendum settings
    super_majority_threshold = models.FloatField(
        null=True, blank=True,
        help_text='e.g. 0.667 for 66.7% threshold (doc: 15-Voting-Engine.md §15.6)'
    )
    abstain_allowed = models.BooleanField(default=False)
    none_of_the_above = models.BooleanField(default=False)

    class Meta:
        db_table = 'positions'
        ordering = ['created_at']

    def __str__(self):
        return f"{self.title} ({self.get_voting_method_display()}, {self.seats_available} seat(s))"


class PositionQuota(TimestampedModel):
    """
    Reserved seat / quota allocation for a designation/position
    e.g. Female: 2 seats, Dalit: 1 seat, Open: 2 seats
    """
    position = models.ForeignKey(
        Position, on_delete=models.CASCADE, related_name='quotas'
    )
    name = models.CharField(max_length=100, help_text='e.g., Female, Dalit, Janajati, Youth, Open')
    seats = models.PositiveIntegerField(default=1, help_text='Number of reserved seats')
    status = models.CharField(
        max_length=20,
        choices=[('active', 'Active'), ('inactive', 'Inactive')],
        default='active'
    )
    description = models.TextField(blank=True, default='')

    class Meta:
        db_table = 'position_quotas'
        ordering = ['created_at']

    def __str__(self):
        return f"{self.position.title} - {self.name} ({self.seats} seats)"


class ElectionRoleAssignment(UUIDModel):
    """
    Per-election role delegation.
    (doc: 08-Database-Design.md §8.2 election_role_assignments table)
    (doc: 10-RBAC-Permissions.md — Election Officer/Observer/Auditor are per-election)
    """
    user = models.ForeignKey(
        'users.User', on_delete=models.CASCADE, related_name='election_roles'
    )
    election = models.ForeignKey(
        Election, on_delete=models.CASCADE, related_name='role_assignments'
    )
    role = models.CharField(
        max_length=20,
        choices=[
            ('election_officer', 'Election Officer'),
            ('observer', 'Observer'),
            ('auditor', 'Auditor'),
        ]
    )
    assigned_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True,
        related_name='role_assignments_made'
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'election_role_assignments'
        unique_together = [['user', 'election', 'role']]
class ElectionNotice(TimestampedModel):
    """
    Announcements or notices for a specific election.
    """
    election = models.ForeignKey(
        Election, on_delete=models.CASCADE, related_name='notices'
    )
    title = models.CharField(max_length=255)
    content = models.TextField()
    is_published = models.BooleanField(default=True)

    class Meta:
        db_table = 'election_notices'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.election.title} - {self.title}"


class ElectionCommittee(TimestampedModel):
    """
    Election committee record — stores the formal committee details
    including the chair's profile and optional signature image.
    The chair_user FK links to the User account that was created or
    selected for this committee chair.
    """
    COMMITTEE_TYPE_NEW = 'new'
    COMMITTEE_TYPE_EXISTING = 'existing'
    COMMITTEE_TYPE_CHOICES = [
        (COMMITTEE_TYPE_NEW, 'Create New Committee'),
        (COMMITTEE_TYPE_EXISTING, 'Select Existing Committee'),
    ]

    election = models.ForeignKey(
        Election, on_delete=models.CASCADE, related_name='committees'
    )
    committee_type = models.CharField(
        max_length=20, choices=COMMITTEE_TYPE_CHOICES, default=COMMITTEE_TYPE_NEW
    )
    committee_name = models.CharField(max_length=255)
    chair_designation = models.CharField(max_length=255, blank=True, default='')
    chair_contact = models.CharField(max_length=100, blank=True, default='')
    chair_email = models.EmailField()
    chair_signature = models.ImageField(
        upload_to='committee_signatures/', null=True, blank=True
    )
    # Populated after the chair user account is created/looked up
    chair_user = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='chaired_committees'
    )
    created_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True,
        related_name='created_committees'
    )
    # The role assigned to the chair_user for this election
    role = models.CharField(
        max_length=50, default='election_officer',
        choices=[
            ('election_officer', 'Election Officer'),
            ('observer', 'Observer'),
            ('auditor', 'Auditor'),
        ]
    )

    class Meta:
        db_table = 'election_committees'
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.committee_name} — {self.election.title}"
