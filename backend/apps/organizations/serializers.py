from rest_framework import serializers
from apps.organizations.models import Organization

class OrganizationSerializer(serializers.ModelSerializer):
    logo_url = serializers.CharField(required=False, allow_blank=True, default='')
    cover_image_url = serializers.CharField(required=False, allow_blank=True, default='')
    bank_qr_url = serializers.CharField(required=False, allow_blank=True, default='')
    website = serializers.CharField(required=False, allow_blank=True, default='')
    email = serializers.EmailField(required=False, allow_blank=True, default='')

    class Meta:
        model = Organization
        fields = [
            'id', 'name', 'slug', 'prefix', 'org_type', 'council_number',
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
            'legal_hold', 'created_at'
        ]
        read_only_fields = ['id', 'slug', 'status', 'trial_ends_at', 'legal_hold', 'created_at']

    def to_internal_value(self, data):
        # Support both 'email' and 'org_email'
        if isinstance(data, dict):
            if 'org_email' in data and 'email' not in data:
                data = dict(data)
                data['email'] = data.pop('org_email')
        return super().to_internal_value(data)

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
