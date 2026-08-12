from apps.organizations.models import Organization
from django.db.models import Count, Q
org = Organization.objects.get(name='New organization')
total_votes_cast = org.elections.aggregate(total=Count('voter_roll', filter=Q(voter_roll__has_voted=True)))['total']
print('Aggregated votes cast for New organization:', total_votes_cast)
