from apps.voting.models import VoterRoll
vr = VoterRoll.objects.filter(has_voted=True).first()
print('VR Election Org:', vr.election.organization.name if vr else None)
from apps.organizations.models import Organization
print('My Org:', Organization.objects.first().name)
