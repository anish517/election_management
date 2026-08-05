"""
Custom User Model
(doc: 08-Database-Design.md §8.2 users table)
(doc: 09-Authentication-Security.md)

Roles:
  - super_admin: Platform-wide (no organization FK)
  - org_admin: Full control of their org
  - election_officer: Per-election delegation (via election_role_assignments)
  - voter: Can vote
  - candidate: Has submitted a nomination
  - observer: Read-only view
  - auditor: Read-only + audit log access
"""
import uuid
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone


class UserRole(models.TextChoices):
    SUPER_ADMIN = 'super_admin', 'Super Admin'
    ORG_ADMIN = 'org_admin', 'Organization Admin'
    ELECTION_OFFICER = 'election_officer', 'Election Officer'
    VOTER = 'voter', 'Voter'
    CANDIDATE = 'candidate', 'Candidate'
    OBSERVER = 'observer', 'Observer'
    AUDITOR = 'auditor', 'Auditor'


class UserManager(BaseUserManager):
    def create_user(self, email, password=None, **extra_fields):
        if not email:
            raise ValueError('Email is required')
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        if password:
            user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault('role', UserRole.SUPER_ADMIN)
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)
        return self.create_user(email, password, **extra_fields)


class User(AbstractBaseUser, PermissionsMixin):
    """
    Custom User model. Supports both org-scoped and platform-wide (Super Admin) users.
    (doc: 08-Database-Design.md §8.2 users table)
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Auth credentials
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20, blank=True, default='')

    # Organization FK — nullable ONLY for Super Admin (doc: 08-Database-Design.md)
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        null=True,  # Null only for super_admin
        blank=True,
        related_name='users',
        db_index=True,
    )

    # Org-wide role (doc: 08-Database-Design.md §8.2 note)
    # Election-scoped roles (officer, observer, auditor per election) are in ElectionRoleAssignment
    role = models.CharField(max_length=20, choices=UserRole.choices, default=UserRole.VOTER)

    # Status
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)  # Django admin access
    is_email_verified = models.BooleanField(default=False)
    is_phone_verified = models.BooleanField(default=False)

    # 2FA (doc: 09-Authentication-Security.md §9.1 — TOTP for admin roles)
    totp_secret = models.CharField(max_length=64, blank=True, default='')
    is_2fa_enabled = models.BooleanField(default=False)

    # Tracking
    last_login_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    # Push notification token (FCM)
    fcm_token = models.TextField(blank=True, default='')

    objects = UserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = []

    class Meta:
        db_table = 'users'
        # One account per email per org; Super Admin excepted (doc: 08-Database-Design.md §8.3)
        constraints = [
            models.UniqueConstraint(
                fields=['organization', 'email'],
                condition=models.Q(organization__isnull=False),
                name='uq_user_org_email'
            )
        ]

    def __str__(self):
        return f"{self.email} ({self.get_role_display()})"

    @property
    def is_super_admin(self):
        return self.role == UserRole.SUPER_ADMIN

    @property
    def is_org_admin(self):
        return self.role == UserRole.ORG_ADMIN

    def update_last_login(self):
        self.last_login_at = timezone.now()
        self.save(update_fields=['last_login_at'])


class OTPRecord(models.Model):
    """
    Stores OTP requests for phone/email verification.
    (doc: 09-Authentication-Security.md §9.1)
    - Valid for 5 minutes
    - Rate-limited to 5 requests per 15 minutes
    - Single-use (invalidated after successful verification)
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    identifier = models.CharField(max_length=255, db_index=True)  # phone or email
    otp_hash = models.CharField(max_length=255)  # Hashed OTP, never plaintext
    purpose = models.CharField(
        max_length=30,
        choices=[
            ('login', 'Login'),
            ('register', 'Registration'),
            ('password_reset', 'Password Reset'),
            ('phone_verify', 'Phone Verification'),
        ]
    )
    is_used = models.BooleanField(default=False)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        db_table = 'otp_records'
        indexes = [
            models.Index(fields=['identifier', 'created_at']),
        ]

    def is_valid(self):
        return not self.is_used and timezone.now() < self.expires_at


class UserDevice(models.Model):
    """
    Tracks active sessions per device for session management.
    (doc: 09-Authentication-Security.md §9.2)
    Org Admin can view and revoke active sessions.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='devices')
    device_id = models.CharField(max_length=255)
    user_agent = models.TextField(blank=True, default='')
    refresh_token_hash = models.CharField(max_length=255)  # Hashed, never plaintext
    last_used_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)
    is_revoked = models.BooleanField(default=False)

    class Meta:
        db_table = 'user_devices'
        unique_together = [['user', 'device_id']]
