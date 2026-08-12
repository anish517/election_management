from apps.organizations.views import OrganizationStatsView
from apps.users.models import User
from rest_framework.test import APIRequestFactory, force_authenticate
import json

factory = APIRequestFactory()
request = factory.get('/v1/organization/stats/')
user = User.objects.get(email='admin@gmail.com')
force_authenticate(request, user=user)

view = OrganizationStatsView.as_view()
response = view(request)
print("Stats JSON:")
print(json.dumps(response.data, indent=2))
