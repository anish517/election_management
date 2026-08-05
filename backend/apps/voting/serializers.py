from rest_framework import serializers
from apps.voting.models import Vote
from apps.elections.models import Position, Election
from apps.candidates.models import Candidate, NominationStatus

class BallotCandidateSerializer(serializers.ModelSerializer):
    name = serializers.CharField(source='member.full_name')
    photo_url = serializers.CharField(source='member.photo_url')
    
    class Meta:
        model = Candidate
        fields = ['id', 'name', 'photo_url', 'manifesto', 'slate_name']


class BallotPositionSerializer(serializers.ModelSerializer):
    candidates = serializers.SerializerMethodField()
    
    class Meta:
        model = Position
        fields = [
            'id', 'title', 'seats_available', 'voting_method', 
            'max_votes_per_voter', 'abstain_allowed', 'none_of_the_above', 'candidates'
        ]
        
    def get_candidates(self, obj):
        # Only APPROVED candidates make it to the ballot
        cands = Candidate.objects.filter(
            position=obj, 
            status=NominationStatus.APPROVED
        ).order_by('?') # For now random, could follow obj.ballot_ordering
        return BallotCandidateSerializer(cands, many=True).data


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
        if election.state != 'voting_active':
            raise serializers.ValidationError("Voting is not currently active for this election.")

        positions = {str(p.id): p for p in election.positions.all()}
        
        for pos_id, cand_ids in ballot_data.items():
            if pos_id not in positions:
                raise serializers.ValidationError(f"Invalid position ID: {pos_id}")
            
            position = positions[pos_id]
            
            # Basic multiple choice / FPTP validation
            if not isinstance(cand_ids, list):
                raise serializers.ValidationError(f"Payload for position {pos_id} must be a list of candidate IDs.")
            
            if len(cand_ids) > position.seats_available:
                raise serializers.ValidationError(f"Too many candidates selected for position {position.title}.")
            
            # Check candidate validity
            for cand_id in cand_ids:
                if not Candidate.objects.filter(id=cand_id, position=position, status=NominationStatus.APPROVED).exists():
                    raise serializers.ValidationError(f"Invalid or unapproved candidate {cand_id} for position {pos_id}.")

        # In production, we'd also validate abstain options, but this covers the MVP.
        return attrs
