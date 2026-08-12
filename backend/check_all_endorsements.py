import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.candidates.models import Candidate

for c in Candidate.objects.all():
    print(f"Candidate: {c.first_name} {c.last_name}")
    print(f"Manifesto: {c.manifesto}")
    print("Endorsements:")
    for e in c.endorsements.all():
        print(f"- {e.endorsement_type}: {e.name}")
    print("---")
