"""
Member Model
(doc: 08-Database-Design.md §8.2 members table)
(doc: 12-Member-Management.md)

The member roster is the source of truth for voter/candidate eligibility.
Members are soft-deleted to preserve historical election integrity.
"""
from django.db import models
from apps.core.models import SoftDeleteModel, TimestampedModel


class MembershipStatus(models.TextChoices):
    INVITED = 'invited', 'Invited'
    ACTIVE = 'active', 'Active'
    SUSPENDED = 'suspended', 'Suspended'
    EXPIRED = 'expired', 'Expired'


class Member(SoftDeleteModel):
    """
    A member of an organization — the source of truth for voter/candidate eligibility.
    (doc: 08-Database-Design.md §8.2 members table)

    Soft-deleted to preserve historical election references.
    (doc: 08-Database-Design.md §8.5)
    """
    # Tenant scoping (required on ALL tenant-scoped models — doc: 07-System-Architecture.md §7.3)
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        related_name='members',
        db_index=True,
    )

    # Link to user account (nullable until member activates their account)
    user = models.ForeignKey(
        'users.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='memberships',
    )

    # Identity
    member_code = models.CharField(max_length=100, help_text='Org-defined member ID')
    prefix = models.CharField(max_length=20, blank=True, default='')
    first_name = models.CharField(max_length=100, blank=True, default='')
    middle_name = models.CharField(max_length=100, blank=True, default='')
    last_name = models.CharField(max_length=100, blank=True, default='')
    full_name = models.CharField(max_length=255)
    photo_url = models.URLField(blank=True, default='')

    # Demographics & IDs
    gender = models.CharField(
        max_length=20,
        choices=[
            ('male', 'Male'), ('female', 'Female'),
            ('other', 'Other'), ('prefer_not_to_say', 'Prefer not to say'),
        ],
        blank=True, default=''
    )
    date_of_birth = models.DateField(null=True, blank=True)
    council_number = models.CharField(max_length=100, blank=True, default='')
    citizenship_number = models.CharField(max_length=100, blank=True, default='')

    # Contact
    email = models.EmailField(blank=True, default='')
    phone = models.CharField(max_length=20, blank=True, default='')
    address = models.TextField(blank=True, default='')

    # Org structure (used in position-level eligibility rules — doc: 12-Member-Management.md §12.6)
    department = models.CharField(max_length=100, blank=True, default='')
    region = models.CharField(max_length=100, blank=True, default='')
    position_title = models.CharField(
        max_length=100, blank=True, default='',
        help_text='Their org role — NOT an election position'
    )

    # Membership lifecycle (doc: 12-Member-Management.md §12.5)
    membership_status = models.CharField(
        max_length=20, choices=MembershipStatus.choices, default=MembershipStatus.INVITED,
        db_index=True,
    )
    membership_expiry_date = models.DateField(null=True, blank=True)

    # Weighted voting support (doc: 15-Voting-Engine.md §15.7)
    voting_weight = models.DecimalField(
        max_digits=10, decimal_places=4, default=1.0,
        help_text='Multiplier for weighted voting (by shareholding, etc.)'
    )

    class Meta:
        db_table = 'members'
        indexes = [
            # Fast eligibility filtering (doc: 08-Database-Design.md §8.3)
            models.Index(fields=['organization', 'membership_status']),
        ]
        constraints = [
            # One member_code per org
            models.UniqueConstraint(
                fields=['organization', 'member_code'],
                name='uq_member_org_code'
            )
        ]

    def __str__(self):
        return f"{self.full_name} ({self.member_code}) — {self.organization.name}"

    @property
    def is_eligible_to_vote(self):
        """
        Base eligibility check — active status only.
        Position-level eligibility_rule is evaluated separately.
        (doc: 12-Member-Management.md §12.5)
        """
        return self.membership_status == MembershipStatus.ACTIVE and self.deleted_at is None

    @property
    def is_eligible_to_nominate(self):
        """Same base check as voting eligibility."""
        return self.is_eligible_to_vote


class MemberImportJob(TimestampedModel):
    """
    Tracks async CSV import jobs for large member imports.
    (doc: 12-Member-Management.md §12.3)
    Imports > 200 rows are processed async via Celery.
    """
    organization = models.ForeignKey(
        'organizations.Organization', on_delete=models.CASCADE,
        related_name='import_jobs'
    )
    initiated_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True
    )
    status = models.CharField(
        max_length=20,
        choices=[
            ('pending', 'Pending'),
            ('processing', 'Processing'),
            ('completed', 'Completed'),
            ('failed', 'Failed'),
        ],
        default='pending'
    )
    file_url = models.URLField(blank=True, default='')
    total_rows = models.IntegerField(default=0)
    created_count = models.IntegerField(default=0)
    updated_count = models.IntegerField(default=0)
    skipped_count = models.IntegerField(default=0)
    error_rows = models.JSONField(default=list)  # [{row: N, reason: '...'}]

    class Meta:
        db_table = 'member_import_jobs'
