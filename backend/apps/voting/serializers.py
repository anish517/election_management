from rest_framework import serializers
from apps.voting.models import Vote
from apps.elections.models import Position, Election
from apps.elections.serializers import PositionQuotaSerializer
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll

class BallotCandidateSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source='full_name')
    photo_url = serializers.CharField(source='candidate_image')
    
    class Meta:
        model = Candidate
        fields = ['id', 'name', 'photo_url', 'manifesto', 'quota_name']


class BallotPositionSerializer(serializers.ModelSerializer):
    candidates = serializers.SerializerMethodField()
    quotas = PositionQuotaSerializer(many=True, read_only=True)
    is_uncontested = serializers.SerializerMethodField()
    
    class Meta:
        model = Position
        fields = [
            'id', 'title', 'seats_available', 'voting_method', 
            'max_votes_per_voter', 'abstain_allowed', 'none_of_the_above', 
            'result_order', 'bg_color', 'quota_name', 'quotas', 'candidates',
            'is_uncontested',
        ]
        
    def get_candidates(self, obj):
        # Only APPROVED candidates make it to the ballot
        cands = Candidate.objects.filter(
            position=obj, 
            status=NominationStatus.APPROVED
        ).order_by('?') # For now random, could follow obj.ballot_ordering
        return BallotCandidateSerializer(cands, many=True).data

    def get_is_uncontested(self, obj):
        approved_count = Candidate.objects.filter(
            position=obj,
            status=NominationStatus.APPROVED
        ).count()
        return 0 < approved_count <= obj.seats_available


class VoterRollSerializer(serializers.ModelSerializer):
    class Meta:
        model = VoterRoll
        fields = [
            'id', 'election', 'voter_id', 'voter_pin', 'prefix', 'first_name', 'middle_name', 'last_name',
            'full_name', 'email', 'phone', 'council_number', 'citizenship_number',
            'is_eligible', 'ineligibility_reason', 'has_voted', 'voted_at',
            'voted_ip_address', 'voted_mac_address',
            'verification_channel', 'verified_at', 'direct_ballot_token_used',
        ]
        read_only_fields = [
            'id', 'election', 'full_name', 'has_voted', 'voted_at',
            'voted_ip_address', 'voted_mac_address',
            'verification_channel', 'verified_at', 'direct_ballot_token_used',
        ]

    def to_representation(self, instance):
        ret = super().to_representation(instance)
        request = self.context.get('request')
        if request and request.user.is_authenticated:
            user = request.user
            is_admin_or_officer = (
                user.role in ['org_admin', 'election_officer', 'super_admin']
                or getattr(user, 'is_org_admin', False)
            )
            if not is_admin_or_officer:
                # Privacy protection: regular voters/candidates only see Name & Voter ID
                ret['email'] = ''
                ret['phone'] = ''
                ret['council_number'] = ''
                ret['citizenship_number'] = ''
                ret['voted_ip_address'] = None
                ret['voted_mac_address'] = ''
        return ret


class CastVoteSerializer(serializers.Serializer):
    """
    Validates a casted ballot.
    Payload expected:
    {
       "position_id_1": ["candidate_uuid"],
       "position_id_2": ["__BOYCOTT__"]
    }
    """
    ballot_data = serializers.JSONField()

    def validate(self, attrs):
        ballot_data = attrs.get('ballot_data', {})
        election = self.context['election']
        
        # Ensure voting is active
        if election.state != 'voting_open':
            raise serializers.ValidationError("Voting is not currently active for this election.")

        positions = {str(p.id): p for p in election.positions.all()}
        
        for pos_id, cand_ids in ballot_data.items():
            if pos_id not in positions:
                raise serializers.ValidationError(f"Invalid position ID: {pos_id}")
            
            pos = positions[pos_id]
            
            if not isinstance(cand_ids, list):
                raise serializers.ValidationError(f"Candidate IDs for {pos.title} must be a list.")
                
            if len(cand_ids) > pos.max_votes_per_voter:
                raise serializers.ValidationError(
                    f"Too many selections for {pos.title}. Max allowed: {pos.max_votes_per_voter}"
                )
                
            for cand_id in cand_ids:
                if cand_id in ['__BOYCOTT__', '__NO_VOTE__', 'NOTA']:
                    continue
                if not Candidate.objects.filter(id=cand_id, position=pos, status=NominationStatus.APPROVED).exists():
                    raise serializers.ValidationError(f"Invalid or unapproved candidate {cand_id} for position {pos_id}.")

        return attrs


class VoterClaimSerializer(serializers.ModelSerializer):
    claim_type_display = serializers.CharField(source='get_claim_type_display', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    resolved_by_email = serializers.EmailField(source='resolved_by.email', read_only=True)

    class Meta:
        from apps.voting.models import VoterClaim
        model = VoterClaim
        fields = [
            'id', 'election', 'claim_type', 'claim_type_display',
            'claimant_name', 'claimant_email', 'claimant_phone', 'claimant_citizenship_number',
            'voter_roll', 'target_voter_name', 'description', 'evidence_file',
            'status', 'status_display', 'resolution_notes',
            'resolved_by', 'resolved_by_email', 'resolved_at', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'election', 'status', 'status_display', 'resolution_notes', 'resolved_by', 'resolved_by_email', 'resolved_at', 'created_at', 'updated_at']
