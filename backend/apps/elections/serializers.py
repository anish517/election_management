from rest_framework import serializers
from apps.elections.models import Election, Position, ElectionStateTransition, ElectionRoleAssignment

class PositionSerializer(serializers.ModelSerializer):
    candidates = serializers.SerializerMethodField()

    class Meta:
        model = Position
        fields = [
            'id', 'title', 'seats_available', 'voting_method',
            'max_votes_per_voter', 'eligibility_rule', 'ballot_ordering',
            'super_majority_threshold', 'abstain_allowed', 'none_of_the_above',
            'candidates', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'candidates', 'created_at', 'updated_at']

    def get_candidates(self, obj):
        # We manually serialize this to avoid circular imports with apps.candidates
        return [
            {
                'id': str(c.id),
                'name': c.member.full_name,
                'photo_url': c.member.photo_url,
                'manifesto': c.manifesto,
                'slate_name': c.slate_name,
                'status': c.status,
                'position': str(obj.id),
                'member': str(c.member.id),
            } for c in obj.candidates.all()
        ]

class ElectionSerializer(serializers.ModelSerializer):
    positions = PositionSerializer(many=True, read_only=True)
    
    class Meta:
        model = Election
        fields = [
            'id', 'title', 'description', 'state', 'voter_roll_freeze_date',
            'voter_roll_frozen_at', 'nomination_open_at', 'nomination_close_at',
            'withdrawal_deadline', 'campaign_silent_from', 'voting_start_at',
            'voting_end_at', 'result_contest_deadline', 'is_secret_ballot',
            'results_visibility', 'live_turnout_enabled', 'resubmission_allowed',
            'positions', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'state', 'voter_roll_frozen_at', 'created_at', 'updated_at']
        
    def validate(self, data):
        # Additional validation (e.g., date ordering) can be added here
        # E.g. nomination_open_at < nomination_close_at < voting_start_at < voting_end_at
        return data

class ElectionStateTransitionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ElectionStateTransition
        fields = ['id', 'from_state', 'to_state', 'triggered_by', 'created_at']
        read_only_fields = ['id', 'from_state', 'to_state', 'triggered_by', 'created_at']
