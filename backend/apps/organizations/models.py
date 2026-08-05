"""
Organization Model (Tenant)
(doc: 08-Database-Design.md §8.2 organizations table)
(doc: 11-Organization-Management.md)

Each organization is a tenant. All core models have an FK to this.
"""
import uuid
from django.db import models
from apps.core.models import TimestampedModel


class OrgType(models.TextChoices):
    COOPERATIVE = 'cooperative', 'Cooperative / SACCO'
    COLLEGE = 'college', 'College / University'
    ASSOCIATION = 'association', 'Professional Association'
    CLUB = 'club', 'Club / Community'
    HOUSING_SOCIETY = 'housing_society', 'Housing Society'
    UNION = 'union', 'Trade Union'
    NGO = 'ngo', 'NGO / INGO'
    CORPORATE = 'corporate', 'Corporate'
    RELIGIOUS = 'religious', 'Religious Organization'
    POLITICAL_PARTY = 'political_party', 'Political Party (Internal)'
    OTHER = 'other', 'Other'


class OrgStatus(models.TextChoices):
    TRIAL = 'trial', 'Trial'
    ACTIVE = 'active', 'Active'
    PAST_DUE = 'past_due', 'Past Due'
    SUSPENDED = 'suspended', 'Suspended'
    CANCELLED = 'cancelled', 'Cancelled'


class Organization(TimestampedModel):
    """
    The primary tenant entity. Every piece of election data belongs to an organization.
    (doc: 08-Database-Design.md §8.2 organizations table)
    """
    # Identity
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255, unique=True)
    org_type = models.CharField(max_length=50, choices=OrgType.choices, default=OrgType.OTHER)

    # Contact / Location
    address = models.TextField(blank=True, default='')
    timezone = models.CharField(max_length=50, default='Asia/Kathmandu')
    default_language = models.CharField(
        max_length=5,
        choices=[('ne', 'Nepali'), ('en', 'English')],
        default='ne'
    )

    # Branding (doc: 11-Organization-Management.md §11.3)
    logo_url = models.URLField(blank=True, default='')
    brand_color = models.CharField(max_length=7, blank=True, default='#1976D2')  # Hex color

    # Subscription & Lifecycle (doc: 11-Organization-Management.md §11.2)
    status = models.CharField(max_length=20, choices=OrgStatus.choices, default=OrgStatus.TRIAL)
    trial_ends_at = models.DateTimeField(null=True, blank=True)
    subscription_plan = models.ForeignKey(
        'billing.SubscriptionPlan',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='organizations',
    )

    # Election Defaults (doc: 11-Organization-Management.md §11.7)
    grievance_window_days = models.PositiveIntegerField(default=3)
    voter_roll_freeze_offset_days = models.IntegerField(
        default=0,
        help_text='Days before nomination-open date. 0 = freeze on nomination-open date.'
    )
    default_nomination_window_days = models.PositiveIntegerField(default=7)
    default_voting_window_days = models.PositiveIntegerField(default=1)
    default_silent_period_hours = models.PositiveIntegerField(default=24)
    default_result_visibility = models.CharField(
        max_length=20,
        choices=[
            ('admin_only', 'Admin Only'),
            ('org_members', 'Org Members'),
            ('public', 'Public'),
        ],
        default='admin_only'
    )
    election_officers_can_publish = models.BooleanField(
        default=False,
        help_text='If True, Election Officers can self-publish results (doc: 10-RBAC-Permissions.md)'
    )

    # Data Retention (doc: 03-Nepal-Election-Workflow.md §3.6)
    data_retention_years = models.PositiveIntegerField(
        default=7,
        help_text='Minimum 1 year enforced at platform level.'
    )
    legal_hold = models.BooleanField(
        default=False,
        help_text='Blocks automated retention-purge jobs (doc: 19-Audit-Compliance.md §19.7)'
    )

    class Meta:
        db_table = 'organizations'
        ordering = ['name']

    def __str__(self):
        return f"{self.name} ({self.get_org_type_display()})"

    @property
    def is_active(self):
        return self.status in [OrgStatus.TRIAL, OrgStatus.ACTIVE]

    def get_voter_cap(self):
        """Returns the voter cap based on the subscription plan."""
        if self.subscription_plan:
            return self.subscription_plan.voter_cap
        from django.conf import settings
        return settings.ORG_TRIAL_VOTER_CAP  # Default trial cap
