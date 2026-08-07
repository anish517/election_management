"""
Authentication Serializers
(doc: 09-Authentication-Security.md §9.1)
(doc: 21-REST-API-Documentation.md §21.1)
"""
import hashlib
import secrets
from django.utils import timezone
from datetime import timedelta
from django.conf import settings
from rest_framework import serializers
from rest_framework_simplejwt.tokens import RefreshToken
from apps.users.models import User, OTPRecord, UserRole
from apps.organizations.models import Organization, OrgType


class RegisterSerializer(serializers.Serializer):
    """
    POST /v1/auth/register/
    Creates an Org Admin + Organization in Trial state.
    (doc: 21-REST-API-Documentation.md §21.1, UC-01)
    """
    email = serializers.EmailField()
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True)
    password = serializers.CharField(min_length=8, write_only=True)
    org_name = serializers.CharField(max_length=255)
    org_type = serializers.ChoiceField(
        choices=OrgType.choices,
        required=False,
        default='other'
    )

    def validate_email(self, value):
        if User.objects.filter(email=value.lower()).exists():
            raise serializers.ValidationError('An account with this email already exists.')
        return value.lower()

    def create(self, validated_data):
        from apps.audit.models import log_action
        from apps.organizations.models import OrgType, OrgStatus
        import re

        # Generate slug from org name
        slug_base = re.sub(r'[^a-z0-9-]', '-', validated_data['org_name'].lower()).strip('-')
        slug = slug_base
        count = 1
        while Organization.objects.filter(slug=slug).exists():
            slug = f"{slug_base}-{count}"
            count += 1

        # Create organization in TRIAL state (doc: 11-Organization-Management.md §11.2)
        org = Organization.objects.create(
            name=validated_data['org_name'],
            slug=slug,
            org_type=validated_data.get('org_type', 'other'),
            status=OrgStatus.TRIAL,
            trial_ends_at=timezone.now() + timedelta(days=settings.ORG_TRIAL_DAYS),
        )

        # Create Org Admin user
        user = User.objects.create_user(
            email=validated_data['email'],
            password=validated_data['password'],
            phone=validated_data.get('phone', ''),
            role=UserRole.ORG_ADMIN,
            organization=org,
        )

        log_action('org.created', organization=org, actor=user, target=org,
                   metadata={'org_name': org.name, 'org_type': org.org_type})

        return user, org


class LoginSerializer(serializers.Serializer):
    """
    POST /v1/auth/login/
    Email/phone + password auth — returns JWT tokens.
    (doc: 09-Authentication-Security.md §9.1)
    """
    email_or_phone = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, attrs):
        identifier = attrs['email_or_phone'].strip()
        password = attrs['password']

        # Try email first, then phone
        user = None
        if '@' in identifier:
            user = User.objects.filter(email=identifier.lower()).first()
        else:
            user = User.objects.filter(phone=identifier).first()

        if not user or not user.check_password(password):
            raise serializers.ValidationError(
                {'non_field_errors': 'Invalid credentials.'},
                code='authentication_failed'
            )

        if not user.is_active:
            raise serializers.ValidationError({'non_field_errors': 'Account is disabled.'})

        attrs['user'] = user
        return attrs

    def get_tokens(self, user):
        refresh = RefreshToken.for_user(user)
        return {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        }


class OTPRequestSerializer(serializers.Serializer):
    """
    POST /v1/auth/otp/request/
    Requests an OTP via SMS or email.
    (doc: 09-Authentication-Security.md §9.1)
    - Rate-limited to 5 per 15 minutes
    """
    phone_or_email = serializers.CharField()
    purpose = serializers.ChoiceField(
        choices=['login', 'register', 'password_reset', 'phone_verify'],
        default='login'
    )

    def validate_phone_or_email(self, value):
        return value.strip()

    def create_otp(self, identifier: str, purpose: str, ip_address: str = None) -> str:
        """
        Generate OTP, store hashed version, return plaintext OTP for delivery.
        """
        # Rate limiting check (doc: 09-Authentication-Security.md §9.1)
        window_start = timezone.now() - timedelta(seconds=settings.OTP_WINDOW_SECONDS)
        recent_count = OTPRecord.objects.filter(
            identifier=identifier,
            created_at__gte=window_start,
        ).count()

        if recent_count >= settings.OTP_MAX_ATTEMPTS_PER_WINDOW:
            raise serializers.ValidationError(
                'Too many OTP requests. Please wait 15 minutes.'
            )

        # Generate 6-digit OTP
        otp = f"{secrets.randbelow(1000000):06d}"
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()

        OTPRecord.objects.create(
            identifier=identifier,
            otp_hash=otp_hash,
            purpose=purpose,
            expires_at=timezone.now() + timedelta(seconds=settings.OTP_EXPIRY_SECONDS),
            ip_address=ip_address,
        )

        return otp


class OTPVerifySerializer(serializers.Serializer):
    """
    POST /v1/auth/otp/verify/
    Verifies OTP and returns JWT tokens.
    (doc: 09-Authentication-Security.md §9.1)
    """
    phone_or_email = serializers.CharField()
    otp = serializers.CharField(max_length=6, min_length=6)

    def validate(self, attrs):
        identifier = attrs['phone_or_email'].strip()
        otp = attrs['otp']
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()

        record = OTPRecord.objects.filter(
            identifier=identifier,
            otp_hash=otp_hash,
            is_used=False,
        ).order_by('-created_at').first()

        if not record or not record.is_valid():
            raise serializers.ValidationError({'otp': 'Invalid or expired OTP.'})

        # Mark as used (single-use, doc: 09-Authentication-Security.md §9.1)
        record.is_used = True
        record.save(update_fields=['is_used'])

        # Find user — first in User table, then fall back to Member roster
        user = None
        if '@' in identifier:
            user = User.objects.filter(email=identifier.lower()).first()
            if not user:
                # Check if this email belongs to a member — auto-create a voter account
                try:
                    from apps.members.models import Member
                    member = Member.objects.filter(
                        email__iexact=identifier.strip(),
                        deleted_at__isnull=True,
                    ).select_related('organization').first()
                    if member and member.organization:
                        user = User.objects.create_user(
                            email=identifier.lower(),
                            role=UserRole.VOTER,
                            organization=member.organization,
                            phone=member.phone or '',
                        )
                        # Link the member record to the new user account
                        member.user = user
                        member.membership_status = 'active'
                        member.save(update_fields=['user', 'membership_status'])
                except Exception:
                    pass
        else:
            user = User.objects.filter(phone=identifier).first()

        if not user:
            raise serializers.ValidationError(
                {'phone_or_email': 'No account found with this identifier. '
                                   'Make sure you are a registered member of an organization.'}
            )

        attrs['user'] = user
        return attrs

    def get_tokens(self, user):
        refresh = RefreshToken.for_user(user)
        return {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        }


class UserProfileSerializer(serializers.ModelSerializer):
    """Read-only user profile — never exposes sensitive fields."""
    organization_name = serializers.SerializerMethodField()
    role_display = serializers.SerializerMethodField()
    full_name = serializers.SerializerMethodField()
    photo_url = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'phone', 'role', 'role_display',
            'organization', 'organization_name',
            'full_name', 'photo_url',
            'is_2fa_enabled', 'last_login_at', 'created_at',
        ]
        read_only_fields = fields

    def get_organization_name(self, obj):
        return obj.organization.name if obj.organization else None

    def get_role_display(self, obj):
        return obj.get_role_display()

    def get_full_name(self, obj):
        member = obj.memberships.filter(deleted_at__isnull=True).first()
        return member.full_name if member else ''

    def get_photo_url(self, obj):
        member = obj.memberships.filter(deleted_at__isnull=True).first()
        return member.photo_url if member else ''
