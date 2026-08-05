from django.contrib import admin
from apps.organizations.models import Organization

@admin.register(Organization)
class OrganizationAdmin(admin.ModelAdmin):
    list_display = ('name', 'org_type', 'status', 'created_at')
    search_fields = ('name', 'slug')
