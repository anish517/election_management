from apps.voting.models import Vote, VoterRoll
print('Votes:', Vote.objects.count())
print('VoterRoll voted:', VoterRoll.objects.filter(has_voted=True).count())
