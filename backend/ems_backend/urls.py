"""
Base URL: /v1/ (doc: 21-REST-API-Documentation.md)
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.routers import DefaultRouter
from rest_framework_nested import routers

from apps.users.views import RegisterView, LoginView, MeView, OTPRequestView, OTPVerifyView, LogoutView
from rest_framework_simplejwt.views import TokenRefreshView
from apps.elections.views import ElectionViewSet, PositionViewSet
from apps.members.views import MemberViewSet
from apps.candidates.views import CandidateViewSet
from apps.voting.views import VotingViewSet, VotingHistoryView
from apps.results.views import ElectionResultsViewSet
from apps.organizations.views import OrganizationView, OrganizationStatsView

# Build the main router
router = routers.SimpleRouter()
router.register(r'members', MemberViewSet, basename='member')
router.register(r'elections', ElectionViewSet, basename='election')
router.register(r'voting/history', VotingHistoryView, basename='voting-history')

# Build the nested router for elections
election_router = routers.NestedSimpleRouter(router, r'elections', lookup='election')
election_router.register(r'positions', PositionViewSet, basename='election-positions')
election_router.register(r'candidates', CandidateViewSet, basename='election-candidates')
election_router.register(r'voting', VotingViewSet, basename='election-voting')
election_router.register(r'results', ElectionResultsViewSet, basename='election-results')

urlpatterns = [
    # Django admin (Super Admin support tool)
    path('admin/', admin.site.urls),

    # API v1 — Auth routes (doc: 21-REST-API-Documentation.md)
    path('v1/auth/register/', RegisterView.as_view(), name='register'),
    path('v1/auth/login/', LoginView.as_view(), name='login'),
    path('v1/auth/logout/', LogoutView.as_view(), name='logout'),
    path('v1/auth/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('v1/auth/me/', MeView.as_view(), name='user-profile'),
    path('v1/auth/otp/request/', OTPRequestView.as_view(), name='otp-request'),
    path('v1/auth/otp/verify/', OTPVerifyView.as_view(), name='otp-verify'),
    
    # Organization Settings
    path('v1/organization/', OrganizationView.as_view(), name='organization-profile'),
    path('v1/organization/stats/', OrganizationStatsView.as_view(), name='organization-stats'),
    
    # Core endpoints (REST)
    path('v1/', include(router.urls)),
    path('v1/', include(election_router.urls)),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
