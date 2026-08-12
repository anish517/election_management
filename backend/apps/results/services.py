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
        votes = Vote.objects.filter(election=position.election)
        pos_id = str(position.id)
        total_valid_ballots = 0
        
        from apps.candidates.models import NominationStatus
        candidates_map = {str(c.id): {'name': c.full_name, 'photo_url': c.candidate_image} for c in Candidate.objects.filter(position=position, status=NominationStatus.APPROVED)}
        seats = position.seats_available
        winners = []
        breakdown = []
        
        # STANDARD METHODS (Simple Summation)
        standard_methods = ['fptp', 'multi_choice', 'approval', 'weighted', 'proxy', 'yes_no']
        if position.voting_method in standard_methods:
            candidate_scores = {cand_id: 0.0 for cand_id in candidates_map}
            for vote in votes:
                if pos_id in vote.ballot_data:
                    total_valid_ballots += 1
                    choices = vote.ballot_data[pos_id]
                    weight = float(vote.weight)
                    for cand_id in choices:
                        candidate_scores[cand_id] += weight
                        
            sorted_scores = sorted(candidate_scores.items(), key=lambda x: x[1], reverse=True)
            if sorted_scores:
                winners = [item[0] for item in sorted_scores[:seats]]
                
        # RANKED CHOICE (Instant Runoff Voting)
        elif position.voting_method == 'ranked_choice':
            ballots = []
            for vote in votes:
                if pos_id in vote.ballot_data:
                    total_valid_ballots += 1
                    ballots.append({'choices': vote.ballot_data[pos_id], 'weight': float(vote.weight)})
                    
            active_candidates = set(candidates_map.keys())
            
            while len(active_candidates) > seats:
                candidate_scores = {cand_id: 0.0 for cand_id in active_candidates}
                total_weight = 0.0
                
                for b in ballots:
                    for choice in b['choices']:
                        if choice in active_candidates:
                            candidate_scores[choice] += b['weight']
                            total_weight += b['weight']
                            break
                            
                if total_weight == 0:
                    break
                    
                sorted_scores = sorted(candidate_scores.items(), key=lambda x: x[1], reverse=True)
                top_cand, top_score = sorted_scores[0]
                
                if seats == 1 and top_score > (total_weight / 2):
                    break # Winner found
                    
                # Eliminate lowest candidate
                lowest_cand = sorted_scores[-1][0]
                active_candidates.remove(lowest_cand)
                
            # Final tally for remaining active candidates
            final_scores = {cand_id: 0.0 for cand_id in active_candidates}
            for b in ballots:
                for choice in b['choices']:
                    if choice in active_candidates:
                        final_scores[choice] += b['weight']
                        break
            
            sorted_scores = sorted(final_scores.items(), key=lambda x: x[1], reverse=True)
            winners = [item[0] for item in sorted_scores[:seats]]
            
        else:
            sorted_scores = []
            
        for cand_id, score in sorted_scores:
            c_info = candidates_map.get(cand_id, {'name': 'Unknown', 'photo_url': ''})
            breakdown.append({
                'candidate_id': cand_id,
                'name': c_info['name'],
                'photo_url': c_info['photo_url'],
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
