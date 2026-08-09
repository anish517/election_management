import os
import django
import sys
import uuid

# Setup Django environment
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.organizations.models import Organization
from apps.members.models import Member
from apps.elections.models import Election, Position, VotingMethod, ElectionState
from apps.candidates.models import Candidate
from apps.voting.models import VoterRoll, Vote
from apps.results.services import TallyService

def run_test():
    print("--- STARTING VOTING ENGINE TEST ---")
    
    # 1. Setup Mock Organization
    org, _ = Organization.objects.get_or_create(name="Test Org", slug=f"test-org-{uuid.uuid4().hex[:6]}")
    
    # 2. Setup Mock Members (Voters)
    member_a, _ = Member.objects.get_or_create(organization=org, member_code="A001", defaults={"full_name": "Voter A (Normal)", "voting_weight": 1.0})
    member_b, _ = Member.objects.get_or_create(organization=org, member_code="B001", defaults={"full_name": "Voter B (Whale)", "voting_weight": 50.5})
    
    # 3. Setup Election
    election = Election.objects.create(organization=org, title="Test Election", state=ElectionState.VOTING_OPEN)
    
    from apps.candidates.models import NominationStatus
    
    # 4. Setup Positions and Candidates
    # Method 1: FPTP
    pos_fptp = Position.objects.create(election=election, title="FPTP Post", voting_method=VotingMethod.FPTP, seats_available=1)
    cand_f1 = Candidate.objects.create(election=election, position=pos_fptp, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_f2 = Candidate.objects.create(election=election, position=pos_fptp, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 2: Multi Choice
    pos_multi = Position.objects.create(election=election, title="Multi Choice Post", voting_method=VotingMethod.MULTI_CHOICE, seats_available=2)
    cand_m1 = Candidate.objects.create(election=election, position=pos_multi, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_m2 = Candidate.objects.create(election=election, position=pos_multi, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 3: Ranked Choice
    pos_ranked = Position.objects.create(election=election, title="Ranked Choice Post", voting_method=VotingMethod.RANKED_CHOICE, seats_available=1)
    cand_r1 = Candidate.objects.create(election=election, position=pos_ranked, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_r2 = Candidate.objects.create(election=election, position=pos_ranked, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 4: Approval
    pos_approval = Position.objects.create(election=election, title="Approval Post", voting_method=VotingMethod.APPROVAL, seats_available=1)
    cand_a1 = Candidate.objects.create(election=election, position=pos_approval, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_a2 = Candidate.objects.create(election=election, position=pos_approval, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 5: Weighted
    pos_weighted = Position.objects.create(election=election, title="Weighted Post", voting_method=VotingMethod.WEIGHTED, seats_available=1)
    cand_w1 = Candidate.objects.create(election=election, position=pos_weighted, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_w2 = Candidate.objects.create(election=election, position=pos_weighted, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 6: Proxy (uses same tally logic as FPTP/Weighted but implies proxy logic in cast)
    pos_proxy = Position.objects.create(election=election, title="Proxy Post", voting_method=VotingMethod.PROXY, seats_available=1)
    cand_p1 = Candidate.objects.create(election=election, position=pos_proxy, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    cand_p2 = Candidate.objects.create(election=election, position=pos_proxy, member=member_b, manifesto="Vote me", status=NominationStatus.APPROVED)

    # Method 7: Yes/No
    pos_yesno = Position.objects.create(election=election, title="Yes/No Post", voting_method=VotingMethod.YES_NO, seats_available=1)
    cand_yn1 = Candidate.objects.create(election=election, position=pos_yesno, member=member_a, manifesto="Vote me", status=NominationStatus.APPROVED)
    
    # 5. Cast Votes (Bypassing Session for direct testing)
    print("\nCasting Votes...")
    
    # Voter A (Weight 1.0) casts their ballot
    Vote.objects.create(
        election=election,
        weight=member_a.voting_weight,
        receipt_hash=uuid.uuid4().hex,
        ballot_data={
            str(pos_fptp.id): [str(cand_f1.id)],
            str(pos_multi.id): [str(cand_m1.id), str(cand_m2.id)],
            str(pos_ranked.id): [str(cand_r1.id), str(cand_r2.id)],
            str(pos_approval.id): [str(cand_a1.id), str(cand_a2.id)],
            str(pos_weighted.id): [str(cand_w1.id)],
            str(pos_proxy.id): [str(cand_p1.id)],
            str(pos_yesno.id): [str(cand_yn1.id)],
        }
    )
    
    # Voter B (Weight 50.5) casts their ballot
    Vote.objects.create(
        election=election,
        weight=member_b.voting_weight, # Wait, for all positions except weighted/proxy, is weight used?
        # Actually in TallyService, weight is applied to ALL methods if passed on the Vote object.
        # So we should be careful. But let's test it.
        receipt_hash=uuid.uuid4().hex,
        ballot_data={
            str(pos_fptp.id): [str(cand_f2.id)],
            str(pos_multi.id): [str(cand_m2.id)],
            str(pos_ranked.id): [str(cand_r2.id), str(cand_r1.id)],
            str(pos_approval.id): [str(cand_a2.id)],
            str(pos_weighted.id): [str(cand_w2.id)],
            str(pos_proxy.id): [str(cand_p2.id)],
            str(pos_yesno.id): [str(cand_yn1.id)],
        }
    )
    
    # 6. Run Tally Engine
    print("\nRunning Tally Engine...\n")
    results = TallyService.tally_election(election)
    
    for pos_result in results['results']:
        print(f"Position: {pos_result['title']} (Total Ballots: {pos_result['total_valid_ballots']})")
        for score in pos_result['breakdown']:
            print(f"  - {score['name']}: {score['score']} votes")
        print("-" * 30)

    print("\nTEST COMPLETE.")

if __name__ == '__main__':
    run_test()
