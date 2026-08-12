import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from rest_framework.renderers import JSONRenderer

from apps.candidates.models import Candidate
from apps.candidates.serializers import CandidateSerializer

c = Candidate.objects.filter(manifesto__icontains="my goal is to built fully").first()
print(JSONRenderer().render(CandidateSerializer(c).data).decode('utf-8'))
