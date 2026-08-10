import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.elections.models import Election, Position, VotingMethod, ElectionState
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import Vote, VoterRoll
from apps.members.models import Member
from apps.organizations.models import Organization
from django.contrib.auth import get_user_model
from django.utils import timezone
from datetime import timedelta

User = get_user_model()

def create_test_elections():
    org = Organization.objects.first()
    if not org:
        print("No organization found.")
        return

    # Ensure we have at least 5 members
    members = list(Member.objects.filter(organization=org)[:10])
    while len(members) < 5:
        m = Member.objects.create(
            organization=org,
            full_name=f"Test Voter {len(members)+1}",
            email=f"testvoter{len(members)+1}_{org.id}@test.com",
            member_code=f"MEM_{len(members)+1}",
            membership_status='active'
        )
        members.append(m)

    # Ensure users exist for these members
    voters = []
    for m in members[:5]:
        user = m.user
        if not user:
            user = User.objects.create(email=f"dummy_{m.id}@test.com", organization=org, role='voter')
            m.user = user
            m.save()
        voters.append(user)

    # Test cases mapped to VotingMethod
    test_cases = [
        (VotingMethod.FPTP, "First-Past-The-Post"),
        (VotingMethod.MULTI_CHOICE, "Multiple Choice"),
        (VotingMethod.RANKED_CHOICE, "Ranked Choice (STV)"),
    ]

    for method, title_suffix in test_cases:
        title = f"Test Election - {title_suffix}"
        print(f"Creating: {title}...")

        # Delete old if exists
        Election.objects.filter(title=title).delete()

        election = Election.objects.create(
            organization=org,
            title=title,
            state=ElectionState.RESULTS_FINAL,  # Show results immediately in UI
            voting_start_at=timezone.now() - timedelta(days=2),
            voting_end_at=timezone.now() - timedelta(days=1),
        )

        position = Position.objects.create(
            election=election,
            title="President",
            voting_method=method,
            seats_available=1 if method != VotingMethod.MULTI_CHOICE else 2
        )

        # Create Candidates
        c1 = Candidate.objects.create(election=election, position=position, member=members[0], status=NominationStatus.APPROVED)
        c2 = Candidate.objects.create(election=election, position=position, member=members[1], status=NominationStatus.APPROVED)
        c3 = Candidate.objects.create(election=election, position=position, member=members[2], status=NominationStatus.APPROVED)
        
        pos_id = str(position.id)

        # Create Votes
        if method == VotingMethod.FPTP:
            # FPTP: Each voter selects 1 candidate. C2 wins with 3 votes, C1 gets 2.
            for v in voters[:2]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c1.id)]}, receipt_hash=f"hash_{v.id}_{method}")
            for v in voters[2:5]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c2.id)]}, receipt_hash=f"hash_{v.id}_{method}")

        elif method == VotingMethod.MULTI_CHOICE:
            # Multi: Voters can select up to 2. C2 and C3 win.
            for v in voters[:2]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c1.id), str(c2.id)]}, receipt_hash=f"hash_{v.id}_{method}")
            for v in voters[2:5]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c2.id), str(c3.id)]}, receipt_hash=f"hash_{v.id}_{method}")

        elif method == VotingMethod.RANKED_CHOICE:
            # Ranked: Voters rank candidates.
            # V1, V2 rank C1 -> C3
            # V3, V4, V5 rank C2 -> C3
            for v in voters[:2]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c1.id), str(c3.id)]}, receipt_hash=f"hash_{v.id}_{method}")
            for v in voters[2:5]:
                Vote.objects.create(election=election, ballot_data={pos_id: [str(c2.id), str(c3.id)]}, receipt_hash=f"hash_{v.id}_{method}")

    print("\n✅ Successfully created test elections with injected votes!")
    print("Check your Flutter app (Elections -> See All -> Results) to see how the UI handles different voting methods!")

if __name__ == '__main__':
    create_test_elections()
