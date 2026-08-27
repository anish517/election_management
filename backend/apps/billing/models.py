"""
Billing Models — Subscription Plans and Payments
(doc: 27-Monetization-Pricing.md)
(doc: 08-Database-Design.md §8.2 subscription_plans, subscriptions, payments)
"""
import uuid
from django.db import models
from apps.core.models import TimestampedModel


class SubscriptionPlan(models.Model):
    """
    Available subscription tiers.
    (doc: 27-Monetization-Pricing.md §27.2)
    Free / Starter / Growth / Enterprise
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100)  # 'Free', 'Starter', 'Growth', 'Enterprise'
    slug = models.SlugField(unique=True)
    voter_cap = models.IntegerField(default=200, help_text='Max active voters. -1 = unlimited')
    price_npr = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    price_usd = models.DecimalField(max_digits=10, decimal_places=2, default=0)
    max_active_elections = models.IntegerField(default=1, help_text='-1 = unlimited')
    includes_sms = models.BooleanField(default=False)
    includes_advanced_voting = models.BooleanField(default=False)  # RCV, weighted, proxy
    includes_live_dashboard = models.BooleanField(default=False)
    includes_audit_export = models.BooleanField(default=False)
    includes_ai_features = models.BooleanField(default=False)
    includes_webhooks = models.BooleanField(default=False)
    includes_custom_domain = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = 'subscription_plans'
        ordering = ['price_npr']

    def __str__(self):
        return f"{self.name} (NPR {self.price_npr}/yr, {self.voter_cap} voters)"


class Subscription(TimestampedModel):
    """Active subscription for an organization."""
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        related_name='subscriptions',
    )
    plan = models.ForeignKey(SubscriptionPlan, on_delete=models.PROTECT)
    status = models.CharField(
        max_length=20,
        choices=[
            ('active', 'Active'),
            ('past_due', 'Past Due'),
            ('cancelled', 'Cancelled'),
        ],
        default='active',
    )
    current_period_start = models.DateTimeField()
    current_period_end = models.DateTimeField()

    class Meta:
        db_table = 'subscriptions'


class PaymentStatus(models.TextChoices):
    PENDING = 'pending', 'Pending Verification'
    VERIFIED = 'verified', 'Verified / Approved'
    REJECTED = 'rejected', 'Rejected'
    COMPLETED = 'completed', 'Completed'
    FAILED = 'failed', 'Failed'


class PaymentMethod(models.TextChoices):
    STATIC_QR_BANK = 'static_qr_bank', 'Static Bank QR'
    STATIC_QR_WALLET = 'static_qr_wallet', 'Digital Wallet QR (eSewa/Khalti/Fonepay)'
    BANK_TRANSFER = 'bank_transfer', 'Direct Bank Transfer'
    CASH_VOUCHER = 'cash_voucher', 'Cash Voucher'


class Payment(TimestampedModel):
    """
    Payment audit ledger for nomination fees and organizational billing.
    Supports Static QR payments with voucher uploads and officer verification.
    """
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        related_name='payments',
    )
    election = models.ForeignKey(
        'elections.Election',
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name='payments',
    )
    candidate = models.ForeignKey(
        'candidates.Candidate',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payments',
    )
    user = models.ForeignKey(
        'users.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='payments',
    )
    subscription = models.ForeignKey(
        Subscription,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=5, default='NPR')
    payment_method = models.CharField(
        max_length=30,
        choices=PaymentMethod.choices,
        default=PaymentMethod.STATIC_QR_BANK,
    )
    
    # Candidate / Payer submission details
    transaction_reference = models.CharField(
        max_length=255,
        blank=True,
        default='',
        help_text='Transaction ID / Voucher Reference Number',
    )
    receipt_image_url = models.URLField(
        blank=True,
        default='',
        help_text='Uploaded payment voucher or screenshot URL',
    )
    payment_notes = models.TextField(blank=True, default='')

    # Legacy gateway compatibility
    gateway = models.CharField(
        max_length=20,
        blank=True,
        default='static_qr',
    )
    gateway_reference = models.CharField(max_length=255, blank=True, default='')

    # Verification state & Officer audit trail
    status = models.CharField(
        max_length=20,
        choices=PaymentStatus.choices,
        default=PaymentStatus.PENDING,
        db_index=True,
    )
    reviewed_by = models.ForeignKey(
        'users.User',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='reviewed_payments',
    )
    reviewed_at = models.DateTimeField(null=True, blank=True)
    rejection_reason = models.TextField(blank=True, default='')

    # Correction / Amendment tracking
    # When admin requests a correction (e.g., wrong TXN ref), this records it
    correction_notes = models.TextField(blank=True, default='', help_text='Latest correction request details from admin')
    # Full history of corrections: [{ "date": ..., "by": ..., "note": ..., "status_before": ... }, ...]
    correction_history = models.JSONField(blank=True, default=list, help_text='Audit trail of all correction requests')

    class Meta:
        db_table = 'payments'
        ordering = ['-created_at']

    def __str__(self):
        return f"Payment {self.id} — NPR {self.amount} ({self.status}) [{self.organization.name}]"
