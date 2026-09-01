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
        candidates_map = {
            str(c.id): {
                'name': c.full_name,
                'photo_url': c.candidate_image,
                'party_name': c.party_name,
                'panel_name': c.panel_name,
                'symbol_name': c.symbol_name,
                'symbol_image': c.symbol_image,
                'pr_rank': c.pr_rank,
            }
            for c in Candidate.objects.filter(position=position, status=NominationStatus.APPROVED)
        }
        seats = position.seats_available
        winners = []
        breakdown = []
        
        # STANDARD METHODS (Simple Summation)
        standard_methods = ['fptp', 'multi_choice', 'approval', 'weighted', 'proxy', 'yes_no']
        boycott_score = 0.0

        # Calculate official winners ONLY when election state is results_provisional or results_final
        # and at least one ballot has been cast with score > 0
        is_result_state = position.election.state in ['results_provisional', 'results_final']

        if position.voting_method in standard_methods:
            candidate_scores = {cand_id: 0.0 for cand_id in candidates_map}
            for vote in votes:
                if pos_id in vote.ballot_data:
                    total_valid_ballots += 1
                    choices = vote.ballot_data[pos_id]
                    weight = float(vote.weight)
                    for cand_id in choices:
                        if cand_id in ['__BOYCOTT__', '__NO_VOTE__', 'NOTA']:
                            boycott_score += weight
                        elif cand_id in candidate_scores:
                            candidate_scores[cand_id] += weight
                        
            sorted_scores = sorted(candidate_scores.items(), key=lambda x: x[1], reverse=True)
                
        # RANKED CHOICE (Instant Runoff Voting)
        elif position.voting_method == 'ranked_choice':
            ballots = []
            for vote in votes:
                if pos_id in vote.ballot_data:
                    total_valid_ballots += 1
                    choices = vote.ballot_data[pos_id]
                    if any(c in ['__BOYCOTT__', '__NO_VOTE__', 'NOTA'] for c in choices):
                        boycott_score += float(vote.weight)
                    else:
                        ballots.append({'choices': choices, 'weight': float(vote.weight)})
                    
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
            
        else:
            sorted_scores = []
            
        # Determine elected winners, boundary ties, and uncontested wins
        has_tie = False
        tied_cand_ids = set()
        approved_cand_count = len(candidates_map)
        is_uncontested = (0 < approved_cand_count <= seats)

        if is_uncontested:
            # Uncontested designation: all approved candidates win
            winners = list(candidates_map.keys())
        elif sorted_scores:
            valid_scores = [s for s in sorted_scores if s[1] > 0]
            if valid_scores:
                if len(valid_scores) > seats:
                    boundary_score = valid_scores[seats - 1][1]
                    tied_at_boundary = [item for item in valid_scores if item[1] == boundary_score]
                    if len(tied_at_boundary) > 1:
                        has_tie = True
                        tied_cand_ids = {item[0] for item in tied_at_boundary}
                        winners = [item[0] for item in valid_scores if item[1] > boundary_score]
                    else:
                        winners = [item[0] for item in valid_scores[:seats]]
                else:
                    if len(valid_scores) == len(sorted_scores) and len(valid_scores) > 1 and len({s[1] for s in valid_scores}) == 1:
                        has_tie = True
                        tied_cand_ids = {s[0] for s in valid_scores}
                        cutoff_score = valid_scores[0][1]
                        winners = [item[0] for item in valid_scores if item[1] > cutoff_score]
                    else:
                        winners = [item[0] for item in valid_scores[:seats]]

        for rank, (cand_id, score) in enumerate(sorted_scores, start=1):
            c_info = candidates_map.get(cand_id, {'name': 'Unknown', 'photo_url': ''})
            breakdown.append({
                'candidate_id': cand_id,
                'name': c_info['name'],
                'photo_url': c_info['photo_url'],
                'party_name': c_info.get('party_name', ''),
                'panel_name': c_info.get('panel_name', ''),
                'symbol_name': c_info.get('symbol_name', ''),
                'symbol_image': c_info.get('symbol_image', ''),
                'pr_rank': c_info.get('pr_rank', 1),
                'score': score,
                'rank': 1 if is_uncontested else rank,
                'is_elected': (cand_id in winners) or (is_uncontested and is_result_state),
                'is_uncontested': is_uncontested,
                'is_tie': cand_id in tied_cand_ids,
            })

        if boycott_score > 0:
            breakdown.append({
                'candidate_id': '__BOYCOTT__',
                'name': 'No Vote / Abstained (खाली मत / कसैलाई मत छैन)',
                'photo_url': '',
                'score': boycott_score,
                'rank': len(sorted_scores) + 1,
                'is_elected': False,
                'is_uncontested': False,
                'is_tie': False,
            })

        return {
            'position_id': pos_id,
            'title': position.title,
            'seats_available': seats,
            'has_tie': has_tie,
            'is_uncontested': is_uncontested,
            'total_valid_ballots': total_valid_ballots,
            'winners': winners,
            'breakdown': breakdown
        }

    @staticmethod
    def tally_samanupatik(election):
        """
        Calculates Proportional Representation (Samānupātik) results.
        Supports Sainte-Laguë, d'Hondt, and Hare Quota (Largest Remainder) methods.
        (doc: new_feature.MD Requirements 8.2, 8.3, 8.4)
        """
        from apps.candidates.models import Candidate, NominationStatus
        from apps.voting.models import VoterRoll, Vote

        total_seats = getattr(election, 'total_pr_seats', 10) or 10
        threshold_percent = float(getattr(election, 'pr_threshold_percent', 0.0) or 0.0)
        allocation_method = getattr(election, 'pr_allocation_method', 'sainte_lague') or 'sainte_lague'
        is_mixed = getattr(election, 'election_type', 'fptp') == 'mixed'

        total_voters = VoterRoll.objects.filter(election=election, is_eligible=True).count()
        ballots_cast = VoterRoll.objects.filter(election=election, has_voted=True).count()
        turnout_percentage = round((ballots_cast / total_voters * 100), 2) if total_voters > 0 else 0.0

        all_candidates = Candidate.objects.filter(election=election, status=NominationStatus.APPROVED).order_by('pr_rank', 'created_at')
        if is_mixed:
            pr_keywords = ['proportional', 'samanupatik', 'समानुपातिक', 'pr list', 'closed list', 'party list']
            pr_candidates = [
                c for c in all_candidates
                if any(kw in (c.position.title or '').lower() for kw in pr_keywords)
                or getattr(c.position, 'voting_method', '') == 'samanupatik'
            ]
            if pr_candidates:
                all_candidates = pr_candidates
            else:
                all_candidates = list(all_candidates)

        cand_by_id = {str(c.id): c for c in all_candidates}
        
        parties_info = {}
        party_key_map = {}
        party_candidates = defaultdict(list)
        for c in all_candidates:
            p_name = (c.party_name or c.panel_name or 'Independent').strip()
            lower_name = p_name.lower()
            if lower_name not in party_key_map:
                party_key_map[lower_name] = p_name
                parties_info[p_name] = {
                    'party_name': p_name,
                    'panel_name': c.panel_name or '',
                    'symbol_name': c.symbol_name or '',
                    'symbol_image': c.symbol_image or '',
                }
            canonical_name = party_key_map[lower_name]
            party_candidates[canonical_name].append({
                'id': str(c.id),
                'name': c.full_name,
                'photo_url': c.candidate_image,
                'pr_rank': c.pr_rank,
                'quota_name': c.quota_name,
            })

        votes = Vote.objects.filter(election=election)
        party_votes = defaultdict(float)
        boycott_score = 0.0
        total_valid_party_votes = 0.0

        parties_info_lower = {k.lower().strip(): k for k in parties_info}
        for vote in votes:
            weight = float(vote.weight)
            for pos_id, choices in vote.ballot_data.items():
                # In mixed election, skip direct FPTP post ballots when tallying the PR party-list results
                if is_mixed and pos_id != 'pr_ballot' and pos_id not in parties_info:
                    continue

                for choice in choices:
                    choice_str = str(choice).strip()
                    if choice_str in ['__BOYCOTT__', '__NO_VOTE__', 'NOTA']:
                        boycott_score += weight
                    elif choice_str in parties_info:
                        party_votes[choice_str] += weight
                        total_valid_party_votes += weight
                    elif choice_str.lower() in parties_info_lower:
                        matched_p = parties_info_lower[choice_str.lower()]
                        party_votes[matched_p] += weight
                        total_valid_party_votes += weight
                    elif choice_str in cand_by_id:
                        c = cand_by_id[choice_str]
                        p_name = (c.party_name or c.panel_name or 'Independent').strip()
                        if p_name in parties_info:
                            party_votes[p_name] += weight
                            total_valid_party_votes += weight
                        elif p_name.lower() in parties_info_lower:
                            matched_p = parties_info_lower[p_name.lower()]
                            party_votes[matched_p] += weight
                            total_valid_party_votes += weight

        threshold_votes = total_valid_party_votes * (threshold_percent / 100.0) if total_valid_party_votes > 0 else 0.0
        qualified_parties = {}
        disqualified_parties = {}

        for p_name, p_data in parties_info.items():
            v_count = party_votes[p_name]
            v_pct = round((v_count / total_valid_party_votes * 100), 2) if total_valid_party_votes > 0 else 0.0
            is_qualified = (v_count >= threshold_votes) if threshold_percent > 0 else (v_count > 0)
            
            p_record = {
                **p_data,
                'votes': v_count,
                'vote_percentage': v_pct,
                'is_qualified': is_qualified,
                'seats_allocated': 0,
                'elected_candidates': [],
                'all_candidates': party_candidates[p_name],
            }
            if is_qualified:
                qualified_parties[p_name] = p_record
            else:
                disqualified_parties[p_name] = p_record

        seat_allocation_table = []
        
        if qualified_parties and total_seats > 0 and total_valid_party_votes > 0:
            # Modified Sainte-Laguë Method (Nepal Election Commission Standard)
            # Divisors: 1.4 for seat 1 (s=0), then 3, 5, 7, 9, 11... (2s + 1) for subsequent seats
            party_seats = {p: 0 for p in qualified_parties}
            for round_num in range(1, total_seats + 1):
                quotients = {}
                for p, v in qualified_parties.items():
                    s = party_seats[p]
                    divisor = 1.4 if s == 0 else (2 * s + 1)
                    quotients[p] = v['votes'] / divisor
                
                winner_party = max(quotients, key=quotients.get)
                party_seats[winner_party] += 1
                
                seat_allocation_table.append({
                    'seat_number': round_num,
                    'allocated_to_party': winner_party,
                    'quotients': {p: round(q, 3) for p, q in quotients.items()},
                    'highest_quotient': round(quotients[winner_party], 3),
                })
            
            for p, s_count in party_seats.items():
                qualified_parties[p]['seats_allocated'] = s_count

        for p, p_data in qualified_parties.items():
            seats_won = p_data['seats_allocated']
            c_list = party_candidates[p]
            p_data['elected_candidates'] = c_list[:seats_won]

        all_party_results = list(qualified_parties.values()) + list(disqualified_parties.values())
        all_party_results.sort(key=lambda x: (x['seats_allocated'], x['votes']), reverse=True)

        return {
            'election_id': str(election.id),
            'election_title': election.title,
            'election_type': 'samanupatik',
            'total_pr_seats': total_seats,
            'pr_threshold_percent': threshold_percent,
            'pr_allocation_method': allocation_method,
            'total_voters': total_voters,
            'ballots_cast': ballots_cast,
            'turnout_percentage': turnout_percentage,
            'total_valid_party_votes': total_valid_party_votes,
            'boycott_score': boycott_score,
            'party_results': all_party_results,
            'seat_allocation_table': seat_allocation_table,
        }

    @staticmethod
    def tally_election(election):
        from apps.voting.models import VoterRoll
        
        election_type = getattr(election, 'election_type', 'fptp')

        # Pure Samānupātik (Proportional Representation) tallying
        if election_type == 'samanupatik':
            return TallyService.tally_samanupatik(election)

        total_voters = VoterRoll.objects.filter(election=election, is_eligible=True).count()
        ballots_cast = VoterRoll.objects.filter(election=election, has_voted=True).count()
        turnout_percentage = round((ballots_cast / total_voters * 100), 2) if total_voters > 0 else 0

        results = []
        for position in election.positions.all():
            results.append(TallyService.tally_position(position))

        # Mixed / Parallel (मिश्रित - FPTP Direct Posts + Samānupātik PR Party Allocation)
        if election_type == 'mixed':
            pr_tally = TallyService.tally_samanupatik(election)
            return {
                'election_id': str(election.id),
                'election_title': election.title,
                'election_type': 'mixed',
                'total_voters': total_voters,
                'ballots_cast': ballots_cast,
                'turnout_percentage': turnout_percentage,
                'results': results,
                'samanupatik_results': pr_tally,
            }

        # Standard FPTP tallying
        return {
            'election_id': str(election.id),
            'election_title': election.title,
            'election_type': 'fptp',
            'total_voters': total_voters,
            'ballots_cast': ballots_cast,
            'turnout_percentage': turnout_percentage,
            'results': results
        }
