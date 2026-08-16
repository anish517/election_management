"""
Audit Log Model — Append-Only
(doc: 19-Audit-Compliance.md)
(doc: 08-Database-Design.md §8.2 audit_logs table)

Rules:
- EVERY state-changing action is logged here.
- Vote CONTENT is NEVER logged — only the event type.
- This table has NO UPDATE or DELETE DB grant for any application role.
- Enforced at PostgreSQL role level (see migrations).
"""
import uuid
from django.db import models
from django.conf import settings


class AuditLog(models.Model):
    """
    Append-only audit log for all state-changing actions.
    (doc: 19-Audit-Compliance.md §19.1 What Gets Logged)
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    # Tenant scoping
    organization = models.ForeignKey(
        'organizations.Organization',
        on_delete=models.CASCADE,
        null=True,   # Null for platform-level events (e.g., org.created)
        blank=True,
        related_name='audit_logs',
        db_index=True,
    )

    # Actor — null for system-triggered actions (Celery tasks)
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='audit_actions',
    )

    # Action type (doc: 19-Audit-Compliance.md §19.1)
    # Format: {entity}.{action} e.g. 'election.published', 'vote.cast', 'nomination.approved'
    action = models.CharField(max_length=100, db_index=True)

    # Polymorphic target reference
    target_type = models.CharField(max_length=50, blank=True, default='')  # e.g. 'election'
    target_id = models.UUIDField(null=True, blank=True)

    # Non-sensitive context only — NEVER vote content (doc: 19-Audit-Compliance.md §19.2)
    metadata = models.JSONField(default=dict, blank=True)

    # IP for security events
    ip_address = models.GenericIPAddressField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        db_table = 'audit_logs'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['organization', 'created_at']),  # Timeline queries
            models.Index(fields=['action']),
            models.Index(fields=['target_type', 'target_id']),
        ]
        # No update/delete permissions — enforced via DB-level grants in migration

    def __str__(self):
        actor = self.actor.email if self.actor else 'system'
        return f"[{self.created_at}] {actor}: {self.action} on {self.target_type}:{self.target_id}"


# ============================================================
# Convenience function to create audit log entries
# Used in services.py across all modules
# ============================================================

def log_action(
    action: str,
    organization=None,
    actor=None,
    target=None,
    metadata: dict = None,
    ip_address: str = None,
):
    """
    Create an audit log entry.

    Usage:
        log_action(
            action='election.published',
            organization=election.organization,
            actor=request.user,
            target=election,
            metadata={'election_title': election.title},
        )

    IMPORTANT: Never include vote content in metadata.
    """
    target_type = ''
    target_id = None
    meta = metadata or {}

    if target is not None:
        if isinstance(target, dict):
            meta = {**target, **meta}
            target_id = meta.get('election_id') or meta.get('target_id')
            target_type = 'election' if 'election_id' in meta else 'custom'
        else:
            target_type = type(target).__name__.lower()
            target_id = getattr(target, 'id', None)

    if not target_id and meta:
        target_id = meta.get('election_id') or meta.get('target_id')

    AuditLog.objects.create(
        organization=organization,
        actor=actor,
        action=action,
        target_type=target_type,
        target_id=target_id,
        metadata=meta,
        ip_address=ip_address,
    )
