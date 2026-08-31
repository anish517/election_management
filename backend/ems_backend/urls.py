"""
Base URL: /v1/ (doc: 21-REST-API-Documentation.md)
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.routers import DefaultRouter
from rest_framework_nested import routers

from apps.users.views import (
    RegisterView, LoginView, MeView, OTPRequestView, OTPVerifyView, LogoutView,
    PasswordResetRequestView, PasswordResetConfirmView,
)
from apps.members.views import MemberViewSet
from rest_framework_simplejwt.views import TokenRefreshView
from apps.elections.views import ElectionViewSet, PositionViewSet, PositionQuotaViewSet, ElectionNoticeViewSet
from apps.candidates.views import CandidateViewSet, CandidateObjectionViewSet
from apps.billing.views import PaymentViewSet
from apps.voting.views import (
    VotingViewSet, VotingHistoryView, VoterRollViewSet, VoterClaimViewSet,
    WebVotingOTPRequestView, WebVotingOTPVerifyView, DirectBallotView, DirectVoteCastView,
    ElectionVerificationStatsView,
    KioskUnlockView, KioskVerifyOTPView, KioskCastVoteView,
)
from apps.results.views import ElectionResultsViewSet
from apps.organizations.views import OrganizationView, OrganizationStatsView
from apps.core.views import FileUploadView
from apps.audit.views import AuditExportView, AuditVerifyHashView, AuditReceiptLookupView, AuditLogsView

# Build the main router
router = routers.SimpleRouter()
router.register(r'members', MemberViewSet, basename='member')
router.register(r'elections', ElectionViewSet, basename='election')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'voting/history', VotingHistoryView, basename='voting-history')

# Build the nested router for elections
election_router = routers.NestedSimpleRouter(router, r'elections', lookup='election')
election_router.register(r'positions', PositionViewSet, basename='election-positions')
election_router.register(r'quotas', PositionQuotaViewSet, basename='election-quotas')
election_router.register(r'candidates', CandidateViewSet, basename='election-candidates')
election_router.register(r'payments', PaymentViewSet, basename='election-payments')
election_router.register(r'voting', VotingViewSet, basename='election-voting')
election_router.register(r'results', ElectionResultsViewSet, basename='election-results')
election_router.register(r'voters', VoterRollViewSet, basename='election-voters')
election_router.register(r'notices', ElectionNoticeViewSet, basename='election-notices')
election_router.register(r'voter-claims', VoterClaimViewSet, basename='election-voter-claims')
election_router.register(r'candidate-objections', CandidateObjectionViewSet, basename='election-candidate-objections')

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
    path('v1/auth/password-reset/request/', PasswordResetRequestView.as_view(), name='password-reset-request'),
    path('v1/auth/password-reset/confirm/', PasswordResetConfirmView.as_view(), name='password-reset-confirm'),
    
    # Organization Settings
    path('v1/organization/', OrganizationView.as_view(), name='organization-profile'),
    path('v1/organization/stats/', OrganizationStatsView.as_view(), name='organization-stats'),
    
    # Core endpoints (REST)
    path('v1/upload/', FileUploadView.as_view(), name='file-upload'),

    # Method 1 (Online/Remote) Web Ballot Link & Verification (doc: Election-Methods.pdf)
    path('v1/voting/request-web-otp/', WebVotingOTPRequestView.as_view(), name='voting-request-web-otp'),
    path('v1/voting/verify-web-otp/', WebVotingOTPVerifyView.as_view(), name='voting-verify-web-otp'),
    path('v1/voting/direct-ballot/<str:token>/', DirectBallotView.as_view(), name='voting-direct-ballot'),
    path('v1/voting/direct-cast/<str:token>/', DirectVoteCastView.as_view(), name='voting-direct-cast'),
    path('v1/elections/<uuid:election_pk>/verification-stats/', ElectionVerificationStatsView.as_view(), name='election-verification-stats'),

    # Method 2 (Venue / Device-Based In-Person Voting Kiosks) (doc: Election-Methods.pdf)
    path('v1/voting/kiosk/unlock/', KioskUnlockView.as_view(), name='kiosk-unlock'),
    path('v1/voting/kiosk/verify-otp/', KioskVerifyOTPView.as_view(), name='kiosk-verify-otp'),
    path('v1/voting/kiosk/cast/', KioskCastVoteView.as_view(), name='kiosk-cast'),

    path('v1/', include(router.urls)),
    path('v1/', include(election_router.urls)),

    # Auditor Verification Portal (doc: 19-Audit-Compliance.md)
    path('v1/elections/<uuid:election_id>/audit/export/', AuditExportView.as_view(), name='audit-export'),
    path('v1/elections/<uuid:election_id>/audit/verify-hash/', AuditVerifyHashView.as_view(), name='audit-verify-hash'),
    path('v1/elections/<uuid:election_id>/audit/receipt/<str:receipt_hash>/', AuditReceiptLookupView.as_view(), name='audit-receipt-lookup'),
    path('v1/elections/<uuid:election_id>/audit/logs/', AuditLogsView.as_view(), name='audit-logs'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
