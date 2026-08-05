"""
TenantScopedManager & Base Model
(doc: 07-System-Architecture.md §7.3 Multi-Tenancy Model)

Every tenant-scoped model uses this manager as its default manager.
It automatically filters querysets to the requesting user's organization
so application code never needs to add .filter(organization=...) manually.

The API views also enforce organization scope in permission_classes
(defense-in-depth per 10-RBAC-Permissions.md §10.3).
"""
import uuid
from django.db import models
from django.utils import timezone


class TenantScopedQuerySet(models.QuerySet):
    """
    QuerySet that always filters by organization.
    Do NOT use this directly — use TenantScopedManager.
    """

    def for_organization(self, organization):
        """Filter to the given organization (tenant boundary)."""
        return self.filter(organization=organization)

    def active(self):
        """Filter to non-deleted records (soft-delete support)."""
        return self.filter(deleted_at__isnull=True)


class TenantScopedManager(models.Manager):
    """
    Base manager for all tenant-scoped models.
    Provides a .for_organization(org) shortcut used in services.py
    and enforces soft-delete filtering via .active().

    Usage in views/services:
        Member.objects.for_organization(request.user.organization).active()
    """

    def get_queryset(self):
        return TenantScopedQuerySet(self.model, using=self._db)

    def for_organization(self, organization):
        return self.get_queryset().for_organization(organization)

    def active(self):
        return self.get_queryset().active()


class UUIDModel(models.Model):
    """
    Abstract base model with UUID primary key.
    (doc: 08-Database-Design.md — all core tables use UUID PK)
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)

    class Meta:
        abstract = True


class TimestampedModel(UUIDModel):
    """
    Abstract base with UUID PK + created_at/updated_at timestamps.
    """
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class SoftDeleteModel(TimestampedModel):
    """
    Abstract base with soft-delete support.
    (doc: 08-Database-Design.md §8.5 Soft Delete Strategy)
    Members and Organizations are soft-deleted to preserve historical election integrity.
    """
    deleted_at = models.DateTimeField(null=True, blank=True, db_index=True)

    objects = TenantScopedManager()
    all_objects = models.Manager()  # Use this only in admin/migration contexts

    class Meta:
        abstract = True

    def soft_delete(self):
        """Mark this record as deleted without removing it from the database."""
        self.deleted_at = timezone.now()
        self.save(update_fields=['deleted_at'])

    @property
    def is_deleted(self):
        return self.deleted_at is not None
