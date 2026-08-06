from collections import defaultdict
from apps.voting.models import Vote
from apps.elections.models import Position
from apps.candidates.models import Candidate

class TallyService:
    @staticmethod
    def tally_position(position):
        """
        Pure deterministic tally function.
        (doc: 15-Voting-Engine.md §15.10)
        """
        # Fetch all anonymized votes for the parent election
        votes = Vote.objects.filter(election=position.election)
        
        # We only care about the choice_data for THIS position
        pos_id = str(position.id)
        
        candidate_scores = defaultdict(float)
        total_valid_ballots = 0
        
        for vote in votes:
            ballot_data = vote.ballot_data
            if pos_id in ballot_data:
                total_valid_ballots += 1
                choices = ballot_data[pos_id]
                weight = float(vote.weight)
                
                # Depending on voting method, we apply weight to choices
                if position.voting_method in ['fptp', 'block_voting', 'approval']:
                    for cand_id in choices:
                        candidate_scores[cand_id] += weight
                        
                # Additional methods like 'stv' would branch here
        
        # Sort candidates by score descending
        sorted_scores = sorted(candidate_scores.items(), key=lambda x: x[1], reverse=True)
        
        # Determine winners based on seats available
        seats = position.seats_available
        winners = []
        if sorted_scores:
            # Basic tie-handling (if nth place ties with n+1th place)
            # MVP: just take the top `seats` strictly by array index
            winners = [item[0] for item in sorted_scores[:seats]]
            
        # Get Candidate objects for the breakdown
        candidates_map = {str(c.id): c.member.full_name for c in Candidate.objects.filter(position=position)}
        
        breakdown = []
        for cand_id, score in sorted_scores:
            breakdown.append({
                'candidate_id': cand_id,
                'name': candidates_map.get(cand_id, 'Unknown'),
                'score': score
            })
            
        return {
            'position_id': pos_id,
            'title': position.title,
            'total_valid_ballots': total_valid_ballots,
            'winners': winners,
            'breakdown': breakdown
        }

    @staticmethod
    def tally_election(election):
        from apps.voting.models import VoterRoll
        from apps.members.models import Member
        
        # Calculate turnout
        total_voters = Member.objects.filter(organization=election.organization, membership_status='active').count()
        ballots_cast = VoterRoll.objects.filter(election=election, has_voted=True).count()
        turnout_percentage = round((ballots_cast / total_voters * 100), 2) if total_voters > 0 else 0

        results = []
        for position in election.positions.all():
            results.append(TallyService.tally_position(position))
            
        return {
            'election_id': str(election.id),
            'election_title': election.title,
            'total_voters': total_voters,
            'ballots_cast': ballots_cast,
            'turnout_percentage': turnout_percentage,
            'results': results
        }
