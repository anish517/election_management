from apps.voting.models import VoterRoll, Vote
from apps.organizations.models import Organization

org = Organization.objects.get(name='New organization')
print("New Org ID:", org.id)
rolls = VoterRoll.objects.filter(election__organization=org)
print("Rolls:")
for r in rolls:
    print(f"  {r.email} - has_voted={r.has_voted}")
    
votes = Vote.objects.filter(election__organization=org)
print(f"Votes: {votes.count()}")
