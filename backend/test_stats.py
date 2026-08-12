from apps.organizations.views import OrganizationStatsView
from rest_framework.test import APIRequestFactory
from apps.users.models import User
factory = APIRequestFactory()
request = factory.get('/v1/organization/stats/')
request.user = User.objects.first()
view = OrganizationStatsView.as_view()
response = view(request)
print(response.data)
