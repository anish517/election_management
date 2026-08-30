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
    # Organization Information
    org_name = serializers.CharField(max_length=255)
    org_type = serializers.ChoiceField(choices=OrgType.choices, required=False, default='other')
    prefix = serializers.CharField(max_length=10, required=False, allow_blank=True, default='')
    council_number = serializers.CharField(max_length=100, required=False, allow_blank=True, default='')
    org_email = serializers.EmailField(required=False, allow_blank=True, default='')
    org_phone = serializers.CharField(max_length=30, required=False, allow_blank=True, default='')
    website = serializers.URLField(required=False, allow_blank=True, default='')
    address = serializers.CharField(required=False, allow_blank=True, default='')
    logo_url = serializers.URLField(required=False, allow_blank=True, default='')
    cover_image_url = serializers.URLField(required=False, allow_blank=True, default='')

    # Bank Details (all optional)
    bank_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    bank_branch = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    bank_account_number = serializers.CharField(max_length=50, required=False, allow_blank=True, default='')
    bank_account_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    bank_swift_code = serializers.CharField(max_length=20, required=False, allow_blank=True, default='')
    bank_qr_url = serializers.URLField(required=False, allow_blank=True, default='')

    # Type-specific metadata (optional JSON)
    type_metadata = serializers.DictField(required=False, default=dict)

    # Organization Admin
    admin_name = serializers.CharField(max_length=255, required=False, allow_blank=True, default='')
    email = serializers.EmailField()
    phone = serializers.CharField(max_length=20, required=False, allow_blank=True)
    password = serializers.CharField(min_length=8, write_only=True)

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
            prefix=validated_data.get('prefix', ''),
            council_number=validated_data.get('council_number', ''),
            phone=validated_data.get('org_phone', ''),
            email=validated_data.get('org_email', ''),
            website=validated_data.get('website', ''),
            address=validated_data.get('address', ''),
            logo_url=validated_data.get('logo_url', ''),
            cover_image_url=validated_data.get('cover_image_url', ''),
            bank_name=validated_data.get('bank_name', ''),
            bank_branch=validated_data.get('bank_branch', ''),
            bank_account_number=validated_data.get('bank_account_number', ''),
            bank_account_name=validated_data.get('bank_account_name', ''),
            bank_swift_code=validated_data.get('bank_swift_code', ''),
            bank_qr_url=validated_data.get('bank_qr_url', ''),
            type_metadata=validated_data.get('type_metadata', {}),
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

        # Create a Member record for the admin so their name appears correctly
        admin_name = validated_data.get('admin_name', '').strip()
        if admin_name:
            try:
                from apps.members.models import Member, MembershipStatus
                name_parts = admin_name.split(' ', 1)
                first_name = name_parts[0]
                last_name = name_parts[1] if len(name_parts) > 1 else ''
                Member.objects.create(
                    organization=org,
                    user=user,
                    first_name=first_name,
                    last_name=last_name,
                    email=user.email,
                    phone=user.phone,
                    membership_status=MembershipStatus.ACTIVE,
                )
            except Exception:
                pass  # Name storage is best-effort; do not block registration

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

    def validate(self, attrs):
        identifier = attrs.get('phone_or_email', '').strip()
        purpose = attrs.get('purpose', 'login')

        if purpose in ['login', 'password_reset']:
            if '@' in identifier:
                user = User.objects.filter(email=identifier.lower()).first()
                if not user:
                    from apps.voting.models import VoterRoll
                    if not VoterRoll.objects.filter(email__iexact=identifier).exists():
                        raise serializers.ValidationError({'phone_or_email': 'No account found with this email. Make sure you are a registered member of an organization.'})
            else:
                user = User.objects.filter(phone=identifier).first()
                if not user:
                    from apps.voting.models import VoterRoll
                    if not VoterRoll.objects.filter(phone=identifier).exists():
                        raise serializers.ValidationError({'phone_or_email': 'No account found with this phone number. Make sure you are a registered member of an organization.'})
        return attrs

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
                # Check if this email belongs to a VoterRoll — auto-create a voter account
                try:
                    from apps.voting.models import VoterRoll
                    voter = VoterRoll.objects.filter(
                        email__iexact=identifier.strip(),
                    ).select_related('election__organization').first()
                    
                    if voter and voter.election and voter.election.organization:
                        user = User.objects.create_user(
                            email=identifier.lower(),
                            role=UserRole.VOTER,
                            organization=voter.election.organization,
                            phone=voter.phone or '',
                        )
                except Exception as e:
                    import logging
                    logging.getLogger(__name__).error(f"Error auto-creating voter: {e}")
                    pass
        else:
            user = User.objects.filter(phone=identifier).first()
            if not user:
                # Check if this phone belongs to a VoterRoll — auto-create a voter account
                try:
                    from apps.voting.models import VoterRoll
                    voter = VoterRoll.objects.filter(
                        phone=identifier.strip(),
                    ).select_related('election__organization').first()
                    
                    if voter and voter.election and voter.election.organization:
                        user = User.objects.create_user(
                            email=voter.email or f"{identifier}@voter.local",
                            role=UserRole.VOTER,
                            organization=voter.election.organization,
                            phone=voter.phone or '',
                        )
                except Exception as e:
                    import logging
                    logging.getLogger(__name__).error(f"Error auto-creating voter: {e}")
                    pass

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
    organization_logo_url = serializers.SerializerMethodField()
    organization_cover_image_url = serializers.SerializerMethodField()
    role_display = serializers.SerializerMethodField()
    full_name = serializers.SerializerMethodField()
    photo_url = serializers.SerializerMethodField()
    enrolled_elections = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            'id', 'email', 'phone', 'role', 'role_display',
            'organization', 'organization_name', 'organization_logo_url', 'organization_cover_image_url',
            'full_name', 'photo_url', 'enrolled_elections',
            'is_2fa_enabled', 'last_login_at', 'created_at',
        ]
        read_only_fields = fields

    def get_organization_name(self, obj):
        return obj.organization.name if obj.organization else None

    def get_organization_logo_url(self, obj):
        return obj.organization.logo_url if obj.organization else None

    def get_organization_cover_image_url(self, obj):
        return obj.organization.cover_image_url if obj.organization else None

    def get_role_display(self, obj):
        return obj.get_role_display()

    def get_full_name(self, obj):
        member = obj.memberships.filter(deleted_at__isnull=True).first()
        return member.full_name if member else ''

    def get_photo_url(self, obj):
        member = obj.memberships.filter(deleted_at__isnull=True).first()
        return member.photo_url if member else ''

    def get_enrolled_elections(self, obj):
        from apps.voting.models import VoterRoll
        from django.db.models import Q
        user_email = obj.email.strip().lower() if obj.email else ''
        user_phone = obj.phone.strip() if obj.phone else ''
        v_filter = Q()
        if user_email:
            v_filter |= Q(email__iexact=user_email)
        if user_phone:
            v_filter |= Q(phone=user_phone)
        if not v_filter:
            return []

        rolls = VoterRoll.objects.filter(v_filter, is_eligible=True).select_related('election')
        return [
            {
                'election_id': str(r.election_id),
                'election_title': r.election.title,
                'voter_id': r.voter_id,
                'has_voted': r.has_voted,
                'state': r.election.state,
            }
            for r in rolls
        ]


# ─── Password Reset Serializers ────────────────────────────────────────────────

# Roles allowed to reset password (voters use OTP login, no password needed)
ADMIN_ROLES = {UserRole.ORG_ADMIN, UserRole.ELECTION_OFFICER, UserRole.SUPER_ADMIN}


class PasswordResetRequestSerializer(serializers.Serializer):
    """
    POST /v1/auth/password-reset/request/
    Sends a password-reset OTP to an org_admin or election_officer email.
    Voters/candidates/observers are REJECTED — they use OTP login instead.
    """
    email = serializers.EmailField()

    def validate_email(self, value):
        return value.strip().lower()

    def validate(self, attrs):
        email = attrs['email']
        user = User.objects.filter(email=email).first()

        if not user:
            raise serializers.ValidationError(
                {'email': 'No account found with this email address.'}
            )

        if user.role not in ADMIN_ROLES:
            raise serializers.ValidationError(
                {'email': 'Password reset is only available for Organization Admins and Election Officers. '
                          'Voters and members can sign in using OTP / Phone instead.'}
            )

        if not user.is_active:
            raise serializers.ValidationError({'email': 'This account has been deactivated.'})

        attrs['user'] = user
        return attrs

    def create_otp(self, identifier: str, ip_address: str = None) -> str:
        """Generate and store a password-reset OTP."""
        window_start = timezone.now() - timedelta(seconds=settings.OTP_WINDOW_SECONDS)
        recent_count = OTPRecord.objects.filter(
            identifier=identifier,
            purpose='password_reset',
            created_at__gte=window_start,
        ).count()

        if recent_count >= settings.OTP_MAX_ATTEMPTS_PER_WINDOW:
            raise serializers.ValidationError(
                'Too many password reset requests. Please wait 15 minutes.'
            )

        otp = f"{secrets.randbelow(1000000):06d}"
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()

        OTPRecord.objects.create(
            identifier=identifier,
            otp_hash=otp_hash,
            purpose='password_reset',
            expires_at=timezone.now() + timedelta(seconds=settings.OTP_EXPIRY_SECONDS),
            ip_address=ip_address,
        )

        return otp


class PasswordResetConfirmSerializer(serializers.Serializer):
    """
    POST /v1/auth/password-reset/confirm/
    Verifies the reset OTP and sets the new password.
    """
    email = serializers.EmailField()
    otp = serializers.CharField(max_length=6, min_length=6)
    new_password = serializers.CharField(min_length=8, write_only=True)
    confirm_password = serializers.CharField(min_length=8, write_only=True)

    def validate_email(self, value):
        return value.strip().lower()

    def validate(self, attrs):
        email = attrs['email']
        otp = attrs['otp']
        new_password = attrs['new_password']
        confirm_password = attrs['confirm_password']

        if new_password != confirm_password:
            raise serializers.ValidationError({'confirm_password': 'Passwords do not match.'})

        # Find user and verify role
        user = User.objects.filter(email=email).first()
        if not user:
            raise serializers.ValidationError({'email': 'No account found with this email.'})

        if user.role not in ADMIN_ROLES:
            raise serializers.ValidationError(
                {'email': 'Password reset is not allowed for this account type.'}
            )

        # Verify OTP
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        record = OTPRecord.objects.filter(
            identifier=email,
            otp_hash=otp_hash,
            purpose='password_reset',
            is_used=False,
        ).order_by('-created_at').first()

        if not record or not record.is_valid():
            raise serializers.ValidationError({'otp': 'Invalid or expired OTP. Please request a new code.'})

        # Mark OTP as used (single-use)
        record.is_used = True
        record.save(update_fields=['is_used'])

        attrs['user'] = user
        return attrs

    def save(self):
        user = self.validated_data['user']
        user.set_password(self.validated_data['new_password'])
        user.save(update_fields=['password', 'updated_at'])
        return user

