import os
import django
import sys

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from django.utils import timezone
from apps.users.models import User
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate
from apps.voting.models import VoterRoll, VotingSession, Vote
from apps.voting.services import BallotService
from apps.results.services import TallyService
import json

def print_step(title):
    print(f"\n{'='*50}\n{title}\n{'='*50}")

print_step("1. Setting up Election State & Voter Rolls")
# Get the admin
admin = User.objects.get(email="testadmin2@sacco.com")
org = admin.organization

# Get the election created in Phase 2
election = Election.objects.filter(organization=org).last()
if not election:
    print("No elections found.")
    sys.exit(1)

# Force state to voting_active
election.state = 'voting_active'
election.save()
print(f"Election '{election.title}' set to 'voting_active'.")

# Make the admin user a member so they can vote
admin_member, _ = org.members.get_or_create(
    email=admin.email,
    defaults={
        'member_code': 'ADMIN-001',
        'full_name': 'Admin User',
        'membership_status': 'active'
    }
)

# Add admin to VoterRoll
voter_roll, _ = VoterRoll.objects.get_or_create(election=election, member=admin_member)
# Reset vote status in case we re-run the script
voter_roll.has_voted = False
voter_roll.save()
VotingSession.objects.filter(voter_roll=voter_roll).delete()
Vote.objects.filter(election=election).delete()

print("Added Admin to VoterRoll.")

print_step("2. Generating Ballot")
ballot = BallotService.generate_ballot(election)
print(json.dumps(ballot, indent=2))

print_step("3. Starting Voting Session")
session_token = BallotService.start_session(voter_roll)
print(f"Generated Session Token: {session_token}")

print_step("4. Casting Vote")
# We need to pick a candidate from the ballot
position_id = ballot[0]['id']
candidates = ballot[0]['candidates']
if not candidates:
    print("No approved candidates found on ballot! Please approve Candidate 2 manually via Admin.")
    # Auto-approve all candidates for this test
    for cand in Candidate.objects.filter(election=election):
        cand.status = 'approved'
        cand.save()
    ballot = BallotService.generate_ballot(election)
    candidates = ballot[0]['candidates']

chosen_candidate_id = candidates[0]['id']
ballot_data = {
    position_id: [chosen_candidate_id]
}
print(f"Submitting payload: {ballot_data}")

try:
    receipt = BallotService.cast_vote(session_token, ballot_data, "127.0.0.1")
    print(f"SUCCESS! Vote casted. Receipt Hash: {receipt}")
except Exception as e:
    print(f"FAILED to cast vote: {e}")

print_step("5. Verifying Idempotency")
voter_roll.refresh_from_db()
try:
    BallotService.start_session(voter_roll)
    print("FAIL: Should not be able to start session after voting.")
except ValueError as e:
    print(f"SUCCESS: Prevented session generation: {e}")

try:
    BallotService.cast_vote(session_token, ballot_data)
    print("FAIL: Should not be able to reuse session token.")
except ValueError as e:
    print(f"SUCCESS: Prevented double vote with same session: {e}")

print_step("6. Tallying Results")
results = TallyService.tally_election(election)
print(json.dumps(results, indent=2))

print("\nPhase 3 Integration Tests Complete!")
