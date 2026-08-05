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


class Payment(TimestampedModel):
    """Payment records for subscription billing."""
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        related_name='payments',
    )
    subscription = models.ForeignKey(Subscription, on_delete=models.SET_NULL, null=True)
    gateway = models.CharField(
        max_length=20,
        choices=[('khalti', 'Khalti'), ('esewa', 'eSewa'), ('stripe', 'Stripe')],
    )
    amount = models.DecimalField(max_digits=10, decimal_places=2)
    currency = models.CharField(max_length=5, default='NPR')
    status = models.CharField(
        max_length=20,
        choices=[('pending', 'Pending'), ('completed', 'Completed'), ('failed', 'Failed')],
        default='pending',
    )
    gateway_reference = models.CharField(max_length=255, blank=True, default='')

    class Meta:
        db_table = 'payments'
