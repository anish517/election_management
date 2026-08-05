"""
Auth URL patterns
(doc: 21-REST-API-Documentation.md §21.1)
"""
from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView
from apps.users.views import (
    RegisterView, LoginView, OTPRequestView,
    OTPVerifyView, LogoutView, MeView,
)

urlpatterns = [
    path('register/', RegisterView.as_view(), name='auth-register'),
    path('login/', LoginView.as_view(), name='auth-login'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),
    path('otp/request/', OTPRequestView.as_view(), name='otp-request'),
    path('otp/verify/', OTPVerifyView.as_view(), name='otp-verify'),
    path('logout/', LogoutView.as_view(), name='auth-logout'),
    path('me/', MeView.as_view(), name='auth-me'),
]
