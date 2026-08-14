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
        fields = ['id', 'name', 'photo_url', 'manifesto', 'slate_name', 'quota_name']


class BallotPositionSerializer(serializers.ModelSerializer):
    candidates = serializers.SerializerMethodField()
    quotas = PositionQuotaSerializer(many=True, read_only=True)
    
    class Meta:
        model = Position
        fields = [
            'id', 'title', 'seats_available', 'voting_method', 
            'max_votes_per_voter', 'abstain_allowed', 'none_of_the_above', 
            'result_order', 'bg_color', 'quota_name', 'quotas', 'candidates'
        ]
        
    def get_candidates(self, obj):
        # Only APPROVED candidates make it to the ballot
        cands = Candidate.objects.filter(
            position=obj, 
            status=NominationStatus.APPROVED
        ).order_by('?') # For now random, could follow obj.ballot_ordering
        return BallotCandidateSerializer(cands, many=True).data


class VoterRollSerializer(serializers.ModelSerializer):
    class Meta:
        model = VoterRoll
        fields = [
            'id', 'election', 'voter_id', 'prefix', 'first_name', 'middle_name', 'last_name',
            'full_name', 'email', 'phone', 'council_number', 'citizenship_number',
            'is_eligible', 'ineligibility_reason', 'has_voted', 'voted_at'
        ]
        read_only_fields = ['id', 'election', 'full_name', 'has_voted', 'voted_at']


class CastVoteSerializer(serializers.Serializer):
    """
    Validates a casted ballot.
    Payload expected:
    {
       "position_id_1": ["candidate_uuid"],
       "position_id_2": ["cand_A", "cand_B"]
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
            
            position = positions[pos_id]
            
            # Basic multiple choice / FPTP validation
            if not isinstance(cand_ids, list):
                raise serializers.ValidationError(f"Payload for position {pos_id} must be a list of candidate IDs.")
            
            # Validate number of choices based on voting method
            if position.voting_method not in ['approval', 'ranked_choice']:
                if len(cand_ids) > position.seats_available:
                    raise serializers.ValidationError(f"Too many candidates selected for position {position.title}.")
            
            # Check candidate validity
            for cand_id in cand_ids:
                if not Candidate.objects.filter(id=cand_id, position=position, status=NominationStatus.APPROVED).exists():
                    raise serializers.ValidationError(f"Invalid or unapproved candidate {cand_id} for position {pos_id}.")

        # In production, we'd also validate abstain options, but this covers the MVP.
        return attrs
