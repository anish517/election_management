"""
Authentication Views
(doc: 09-Authentication-Security.md)
(doc: 21-REST-API-Documentation.md §21.1)
"""
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework import status
from rest_framework_simplejwt.views import TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.serializers import (
    RegisterSerializer, LoginSerializer,
    OTPRequestSerializer, OTPVerifySerializer,
    UserProfileSerializer,
    PasswordResetRequestSerializer, PasswordResetConfirmSerializer,
)
from apps.users.services import OTPService
from apps.audit.models import log_action


def get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0].strip()
    return request.META.get('REMOTE_ADDR')


class RegisterView(APIView):
    """
    POST /v1/auth/register/
    Creates Org Admin + Organization (Trial state).
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        if not serializer.is_valid():
            import logging
            logging.getLogger(__name__).warning(f"[Registration Error] Data: {request.data} | Errors: {serializer.errors}")
            serializer.is_valid(raise_exception=True)
        user, org = serializer.create(serializer.validated_data)

        refresh = RefreshToken.for_user(user)
        return Response({
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserProfileSerializer(user).data,
            'organization': {
                'id': str(org.id),
                'name': org.name,
                'status': org.status,
                'trial_ends_at': org.trial_ends_at,
            }
        }, status=status.HTTP_201_CREATED)


class LoginView(APIView):
    """
    POST /v1/auth/login/
    Email/phone + password → JWT tokens.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']

        tokens = serializer.get_tokens(user)
        user.update_last_login()

        log_action(
            'user.login',
            organization=user.organization,
            actor=user,
            target=user,
            ip_address=get_client_ip(request),
        )

        return Response({
            **tokens,
            'user': UserProfileSerializer(user).data,
        })


class OTPRequestView(APIView):
    """
    POST /v1/auth/otp/request/
    Send OTP via SMS/email. Rate-limited to 5/15min.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        identifier = serializer.validated_data['phone_or_email']
        purpose = serializer.validated_data['purpose']
        otp = serializer.create_otp(identifier, purpose, get_client_ip(request))

        # Deliver OTP via the appropriate channel
        OTPService.deliver(identifier, otp, purpose)

        return Response({'otp_sent': True})


class OTPVerifyView(APIView):
    """
    POST /v1/auth/otp/verify/
    Verify OTP → JWT tokens.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = OTPVerifySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']

        tokens = serializer.get_tokens(user)
        user.update_last_login()

        log_action(
            'user.login',
            organization=user.organization,
            actor=user,
            target=user,
            ip_address=get_client_ip(request),
            metadata={'method': 'otp'},
        )

        return Response({
            **tokens,
            'user': UserProfileSerializer(user).data,
        })


class LogoutView(APIView):
    """
    POST /v1/auth/logout/
    Blacklists the refresh token.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            token = RefreshToken(refresh_token)
            token.blacklist()
        except Exception:
            pass  # Token may already be expired/blacklisted

        log_action(
            'session.revoked',
            organization=request.user.organization,
            actor=request.user,
            target=request.user,
            ip_address=get_client_ip(request),
        )

        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(APIView):
    """
    GET /v1/auth/me/ - Current user profile.
    PATCH /v1/auth/me/ - Update profile fields (like photo_url on linked member).
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserProfileSerializer(request.user).data)

    def patch(self, request):
        # Allow updating photo_url on the linked member record
        photo_url = request.data.get('photo_url')
        if photo_url is not None:
            member = request.user.memberships.filter(deleted_at__isnull=True).first()
            if member:
                member.photo_url = photo_url
                member.save(update_fields=['photo_url'])
            elif request.user.organization:
                # Create a Member record for Org Admins who don't have one
                from apps.members.models import Member, MembershipStatus
                full_name = request.user.email.split('@')[0].replace('.', ' ').title()
                Member.objects.create(
                    user=request.user,
                    organization=request.user.organization,
                    email=request.user.email,
                    phone=request.user.phone,
                    full_name=full_name,
                    member_code=f"ADM-{str(request.user.id)[:6].upper()}",
                    membership_status=MembershipStatus.ACTIVE,
                    photo_url=photo_url,
                )
        
        return Response(UserProfileSerializer(request.user).data)


class PasswordResetRequestView(APIView):
    """
    POST /v1/auth/password-reset/request/
    Sends a 6-digit OTP to an org_admin or election_officer email.
    Voters/candidates/observers are rejected with a descriptive error.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = serializer.validated_data['user']
        email = serializer.validated_data['email']
        otp = serializer.create_otp(email, ip_address=get_client_ip(request))

        OTPService.deliver(email, otp, 'password_reset')

        log_action(
            'user.password_reset_requested',
            organization=user.organization,
            actor=user,
            target=user,
            ip_address=get_client_ip(request),
        )

        return Response({'otp_sent': True})


class PasswordResetConfirmView(APIView):
    """
    POST /v1/auth/password-reset/confirm/
    Verifies OTP and resets the user's password.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = PasswordResetConfirmSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        user = serializer.save()

        log_action(
            'user.password_reset',
            organization=user.organization,
            actor=user,
            target=user,
            ip_address=get_client_ip(request),
        )

        return Response({'password_reset': True})
