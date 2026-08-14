import uuid
from django.db import models
from apps.core.models import TimestampedModel


class EmailBroadcastStatus(models.TextChoices):
    QUEUED = 'queued', 'Queued'
    SENT = 'sent', 'Sent'
    FAILED = 'failed', 'Failed'


class EmailBroadcastLog(TimestampedModel):
    """
    Log of broadcast and notification emails sent for elections.
    Stores delivery status (sent/failed) and error reasons for tracking.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    organization = models.ForeignKey(
        'organizations.Organization', on_delete=models.CASCADE, related_name='email_broadcast_logs'
    )
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, null=True, blank=True, related_name='email_broadcast_logs'
    )
    recipient_email = models.EmailField(max_length=255, db_index=True)
    recipient_name = models.CharField(max_length=255, blank=True, default='')
    subject = models.CharField(max_length=255)
    body_html = models.TextField(blank=True, default='')
    recipient_group = models.CharField(max_length=50, blank=True, default='voters')
    status = models.CharField(
        max_length=20, choices=EmailBroadcastStatus.choices, default=EmailBroadcastStatus.QUEUED, db_index=True
    )
    error_message = models.TextField(blank=True, default='')
    sent_at = models.DateTimeField(null=True, blank=True)
    sender = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True, blank=True, related_name='broadcast_emails_sent'
    )

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['election', 'status', 'created_at']),
            models.Index(fields=['organization', 'recipient_email']),
        ]

    def __str__(self):
        return f"Email to {self.recipient_email} - {self.subject} ({self.status})"
