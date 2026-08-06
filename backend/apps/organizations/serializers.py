from rest_framework import serializers
from apps.organizations.models import Organization

class OrganizationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Organization
        fields = [
            'id', 'name', 'slug', 'org_type', 'address', 'timezone', 
            'default_language', 'logo_url', 'brand_color',
            'status', 'trial_ends_at',
            'grievance_window_days', 'voter_roll_freeze_offset_days',
            'default_nomination_window_days', 'default_voting_window_days',
            'default_silent_period_hours', 'default_result_visibility',
            'election_officers_can_publish', 'data_retention_years',
            'legal_hold', 'created_at'
        ]
        read_only_fields = ['id', 'slug', 'status', 'trial_ends_at', 'legal_hold', 'created_at']

class OrganizationStatsSerializer(serializers.Serializer):
    total_members = serializers.IntegerField()
    total_elections = serializers.IntegerField()
    active_elections = serializers.IntegerField()
