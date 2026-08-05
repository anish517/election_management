from rest_framework import serializers
from apps.members.models import Member, MemberImportJob

class MemberSerializer(serializers.ModelSerializer):
    class Meta:
        model = Member
        fields = [
            'id', 'member_code', 'full_name', 'photo_url', 'gender',
            'email', 'phone', 'department', 'region', 'position_title',
            'membership_status', 'membership_expiry_date', 'voting_weight',
            'is_eligible_to_vote', 'is_eligible_to_nominate', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'is_eligible_to_vote', 'is_eligible_to_nominate', 'created_at', 'updated_at']

class MemberImportJobSerializer(serializers.ModelSerializer):
    class Meta:
        model = MemberImportJob
        fields = '__all__'
        read_only_fields = ['id', 'status', 'total_rows', 'created_count', 'updated_count', 'skipped_count', 'error_rows', 'created_at', 'updated_at']
