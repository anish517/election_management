from rest_framework import serializers
from apps.elections.models import Election, Position, PositionQuota, ElectionStateTransition, ElectionRoleAssignment, ElectionNotice, ElectionCommittee


class PositionQuotaSerializer(serializers.ModelSerializer):
    position_title = serializers.CharField(source='position.title', read_only=True)
    election_id = serializers.UUIDField(source='position.election_id', read_only=True)

    class Meta:
        model = PositionQuota
        fields = [
            'id', 'position', 'position_title', 'election_id', 'name', 'seats',
            'status', 'description', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'position_title', 'election_id', 'created_at', 'updated_at']

    def validate(self, data):
        position = data.get('position') or (self.instance.position if self.instance else None)
        seats = data.get('seats', self.instance.seats if self.instance else 1)
        status_val = data.get('status', self.instance.status if self.instance else 'active')

        if position:
            if seats > position.seats_available:
                raise serializers.ValidationError({
                    'seats': f"Allocated seats ({seats}) cannot exceed the designation's total available seats ({position.seats_available})."
                })

            if status_val == 'active':
                existing_active = PositionQuota.objects.filter(position=position, status='active')
                if self.instance:
                    existing_active = existing_active.exclude(id=self.instance.id)
                total_active_seats = sum(q.seats for q in existing_active) + seats
                if total_active_seats > position.seats_available:
                    raise serializers.ValidationError({
                        'seats': f"Total active quota seats ({total_active_seats}) would exceed available seats ({position.seats_available}). Max remaining for this quota is {position.seats_available - sum(q.seats for q in existing_active)}."
                    })

        return data


class PositionSerializer(serializers.ModelSerializer):
    candidates = serializers.SerializerMethodField()
    quotas = PositionQuotaSerializer(many=True, read_only=True)

    class Meta:
        model = Position
        fields = [
            'id', 'title', 'seats_available', 'voting_method',
            'quota_name', 'bg_color', 'result_order', 'nominee_charge',
            'max_votes_per_voter', 'eligibility_rule', 'ballot_ordering',
            'super_majority_threshold', 'abstain_allowed', 'none_of_the_above',
            'quotas', 'candidates', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'quotas', 'candidates', 'created_at', 'updated_at']

    def get_candidates(self, obj):
        # We manually serialize this to avoid circular imports with apps.candidates
        return [
            {
                'id': str(c.id),
                'name': c.full_name,
                'photo_url': c.candidate_image,
                'candidate_image': c.candidate_image,
                'candidate_signature': c.candidate_signature,
                'personal_description': c.personal_description,
                'contribution_to_org': c.contribution_to_org,
                'manifesto': c.manifesto,
                'slate_name': c.slate_name,
                'status': c.status,
                'position': str(obj.id),
                'position_title': obj.title,
                'quota': str(c.quota_id) if c.quota_id else None,
                'quota_name': c.quota_name,
                'email': c.email,
                'contact_number': c.contact_number,
                'gender': c.gender,
                'date_of_birth': str(c.date_of_birth) if c.date_of_birth else None,
                'address': c.address,
                'review_notes': c.review_notes,
                'endorsements': [
                    {
                        'id': str(e.id),
                        'endorsement_type': e.endorsement_type,
                        'name': e.name,
                        'citizenship_number': e.citizenship_number,
                        'phone': e.phone,
                        'membership_id': e.membership_id,
                        'signature_url': e.signature_url,
                    } for e in c.endorsements.all()
                ]
            } for c in obj.candidates.all()
        ]

class ElectionSerializer(serializers.ModelSerializer):
    positions = PositionSerializer(many=True, read_only=True)
    
    class Meta:
        model = Election
        fields = [
            'id', 'title', 'description', 'guidelines',
            # Branding
            'prefix', 'logo_url', 'contact_number', 'primary_color', 'secondary_color',
            # State
            'state',
            # Voter roll
            'voter_roll_freeze_date', 'voter_roll_frozen_at',
            # Voter list schedule
            'first_voter_list_date', 'voter_list_claim_date', 'final_voter_list_date',
            # Candidacy schedule
            'nomination_open_at', 'nomination_close_at',
            'candidacy_claim_date', 'candidacy_final_date',
            # Election schedule
            'withdrawal_deadline', 'campaign_silent_from',
            'voting_start_at', 'voting_end_at', 'result_contest_deadline',
            # Payment
            'is_paid_candidacy', 'nominee_charge',
            # Ballot settings
            'is_secret_ballot', 'results_visibility', 'live_turnout_enabled', 'resubmission_allowed',
            # Positions
            'positions',
            # Timestamps
            'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'state', 'voter_roll_frozen_at', 'created_at', 'updated_at']
        
    def validate(self, data):
        # Validate date ordering where both are provided
        vs = data.get('voting_start_at')
        ve = data.get('voting_end_at')
        if vs and ve and vs >= ve:
            raise serializers.ValidationError('Voting end must be after voting start.')
        no = data.get('nomination_open_at')
        nc = data.get('nomination_close_at')
        if no and nc and no >= nc:
            raise serializers.ValidationError('Candidacy end must be after candidacy start.')
        return data


class ElectionStateTransitionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ElectionStateTransition
        fields = '__all__'

class ElectionNoticeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ElectionNotice
        fields = ['id', 'election', 'title', 'content', 'is_published', 'created_at']
        read_only_fields = ['id', 'election', 'created_at']


class ElectionCommitteeSerializer(serializers.ModelSerializer):
    chair_user_email = serializers.SerializerMethodField()

    class Meta:
        model = ElectionCommittee
        fields = [
            'id', 'election', 'committee_type', 'committee_name',
            'chair_designation', 'chair_contact', 'chair_email',
            'chair_signature', 'chair_user', 'chair_user_email',
            'role', 'created_at'
        ]
        read_only_fields = ['id', 'election', 'chair_user', 'created_at']

    def get_chair_user_email(self, obj):
        return obj.chair_user.email if obj.chair_user else obj.chair_email
