from rest_framework import serializers
from apps.organizations.models import Organization, clean_org_prefix

class OrganizationSerializer(serializers.ModelSerializer):
    logo_url = serializers.CharField(required=False, allow_blank=True, default='')
    cover_image_url = serializers.CharField(required=False, allow_blank=True, default='')
    bank_qr_url = serializers.CharField(required=False, allow_blank=True, default='')
    website = serializers.CharField(required=False, allow_blank=True, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')

    class Meta:
        model = Organization
        fields = [
            'id', 'name', 'slug', 'prefix', 'portal_token', 'org_type', 'council_number',
            'address', 'phone', 'email', 'website', 'timezone',
            'default_language', 'logo_url', 'cover_image_url', 'brand_color',
            'type_metadata',
            'bank_name', 'bank_branch', 'bank_account_number',
            'bank_account_name', 'bank_swift_code', 'bank_qr_url',
            'payment_settings',
            'status', 'trial_ends_at',
            'grievance_window_days', 'voter_roll_freeze_offset_days',
            'default_nomination_window_days', 'default_voting_window_days',
            'default_silent_period_hours', 'default_result_visibility',
            'election_officers_can_publish', 'data_retention_years',
            'legal_hold', 'voting_time_only_mode', 'auto_dispatch_ballot_links',
            'auto_send_vote_receipts', 'created_at'
        ]
        read_only_fields = ['id', 'slug', 'prefix', 'portal_token', 'status', 'trial_ends_at', 'legal_hold', 'created_at']

    def to_internal_value(self, data):
        # Support both 'email' and 'org_email'
        if isinstance(data, dict):
            if 'org_email' in data and 'email' not in data:
                data = dict(data)
                data['email'] = data.pop('org_email')
        return super().to_internal_value(data)

    def validate_prefix(self, value):
        try:
            return clean_org_prefix(value, exclude_id=self.instance.id if self.instance else None)
        except ValueError as e:
            raise serializers.ValidationError(str(e))

    def validate_website(self, value):
        if not value:
            return ''
        value = str(value).strip()
        if value and not value.startswith(('http://', 'https://')):
            value = f'https://{value}'
        return value

class OrganizationStatsSerializer(serializers.Serializer):
    total_members = serializers.IntegerField()
    total_elections = serializers.IntegerField()
    active_elections = serializers.IntegerField()
    total_votes_cast = serializers.IntegerField(default=0)
    turnout_percentage = serializers.FloatField(default=0.0)
    voting_progress = serializers.ListField(
        child=serializers.DictField(), required=False
    )
    results_overview = serializers.ListField(
        child=serializers.DictField(), required=False
    )


class PlatformOrganizationSerializer(serializers.ModelSerializer):
    """
    Super Admin console view of a tenant: identity, lifecycle and size.
    Only status and trial_ends_at are writable from the console.
    """
    member_count = serializers.IntegerField(read_only=True)
    election_count = serializers.IntegerField(read_only=True)
    voter_count = serializers.IntegerField(read_only=True)
    admin_emails = serializers.SerializerMethodField()

    class Meta:
        model = Organization
        fields = [
            'id', 'name', 'slug', 'prefix', 'portal_token', 'org_type', 'email', 'phone', 'logo_url',
            'status', 'trial_ends_at', 'created_at',
            'member_count', 'election_count', 'voter_count', 'admin_emails',
        ]
        read_only_fields = [
            'id', 'name', 'slug', 'prefix', 'portal_token', 'org_type', 'email', 'phone', 'logo_url', 'created_at',
        ]

    def get_admin_emails(self, obj):
        return [u.email for u in obj.users.all() if u.role == 'org_admin']


class PlatformElectionSerializer(serializers.Serializer):
    """Read-only election summary for the Super Admin console."""
    id = serializers.UUIDField()
    title = serializers.CharField()
    state = serializers.CharField()
    state_display = serializers.CharField(source='get_state_display')
    election_type = serializers.CharField()
    election_method = serializers.CharField()
    voting_start_at = serializers.DateTimeField()
    voting_end_at = serializers.DateTimeField()
    created_at = serializers.DateTimeField()
    position_count = serializers.IntegerField()
    voter_count = serializers.IntegerField()
    voted_count = serializers.IntegerField()


class OrgBadgeSerializer(serializers.Serializer):
    """Just enough of an organization to label an election in a list."""
    id = serializers.UUIDField()
    name = serializers.CharField()
    prefix = serializers.CharField()
    logo_url = serializers.CharField()


class PlatformOverviewElectionSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    title = serializers.CharField()
    state = serializers.CharField()
    state_display = serializers.CharField(source='get_state_display')
    voting_start_at = serializers.DateTimeField()
    voting_end_at = serializers.DateTimeField()
    organization = OrgBadgeSerializer()


class PublicElectionSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    title = serializers.CharField()
    state = serializers.CharField()
    state_display = serializers.CharField(source='get_state_display')
    election_method = serializers.CharField(source='get_election_method_display')
    nomination_open_at = serializers.DateTimeField()
    voting_start_at = serializers.DateTimeField()
    voting_end_at = serializers.DateTimeField()


class PublicOrganizationSerializer(serializers.ModelSerializer):
    """An organization's public page (electionnepal.org/<prefix>): no private settings."""

    class Meta:
        model = Organization
        fields = [
            'id', 'name', 'prefix', 'portal_token', 'org_type', 'address', 'phone', 'email', 'website',
            'logo_url', 'cover_image_url', 'brand_color',
        ]


class PlatformCandidateSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    full_name = serializers.CharField()
    status = serializers.CharField()
    status_display = serializers.CharField(source='get_status_display')
    candidate_image = serializers.CharField()


class PlatformPositionSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    title = serializers.CharField()
    seats_available = serializers.IntegerField()
    voting_method = serializers.CharField(source='get_voting_method_display')
    quota_name = serializers.CharField()
    candidates = PlatformCandidateSerializer(many=True)


class PlatformElectionDetailSerializer(serializers.Serializer):
    """
    Read-only election overview for the Super Admin console. No vote tallies:
    those stay behind the results publication flow.
    """
    id = serializers.UUIDField()
    title = serializers.CharField()
    description = serializers.CharField()
    prefix = serializers.CharField()
    logo_url = serializers.CharField()
    state = serializers.CharField()
    state_display = serializers.CharField(source='get_state_display')
    election_type = serializers.CharField(source='get_election_type_display')
    election_method = serializers.CharField(source='get_election_method_display')
    online_type = serializers.CharField(source='get_online_type_display')
    venue_name = serializers.CharField()
    venue_address = serializers.CharField()
    is_secret_ballot = serializers.BooleanField()
    is_paid_candidacy = serializers.BooleanField()
    nominee_charge = serializers.DecimalField(max_digits=10, decimal_places=2)
    results_visibility = serializers.CharField(source='get_results_visibility_display')
    created_at = serializers.DateTimeField()
    schedule = serializers.SerializerMethodField()
    positions = PlatformPositionSerializer(many=True)
    voters = serializers.SerializerMethodField()
    history = serializers.SerializerMethodField()

    _SCHEDULE = [
        ('first_voter_list_date', 'First voter list'),
        ('voter_list_claim_date', 'Voter list claims'),
        ('final_voter_list_date', 'Final voter list'),
        ('voter_roll_freeze_date', 'Voter roll freeze'),
        ('nomination_open_at', 'Nominations open'),
        ('nomination_close_at', 'Nominations close'),
        ('candidacy_claim_date', 'Candidacy claims'),
        ('candidacy_final_date', 'Final candidate list'),
        ('withdrawal_deadline', 'Withdrawal deadline'),
        ('campaign_silent_from', 'Silent period from'),
        ('voting_start_at', 'Voting starts'),
        ('voting_end_at', 'Voting ends'),
        ('result_contest_deadline', 'Result contest deadline'),
    ]

    def get_schedule(self, obj):
        rows = []
        for field, label in self._SCHEDULE:
            value = getattr(obj, field, None)
            if value:
                rows.append({'label': label, 'at': value.isoformat()})
        return rows

    def get_voters(self, obj):
        from django.db.models import Count, Q
        agg = obj.voter_roll.aggregate(
            total=Count('id'),
            eligible=Count('id', filter=Q(is_eligible=True)),
            voted=Count('id', filter=Q(has_voted=True)),
        )
        return agg

    def get_history(self, obj):
        return [
            {
                'from_state': t.get_from_state_display(),
                'to_state': t.get_to_state_display(),
                'at': t.created_at.isoformat(),
            }
            for t in obj.state_transitions.order_by('created_at')
        ]
