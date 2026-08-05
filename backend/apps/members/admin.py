from django.contrib import admin
from apps.members.models import Member

@admin.register(Member)
class MemberAdmin(admin.ModelAdmin):
    list_display = ('full_name', 'member_code', 'organization', 'membership_status')
    list_filter = ('membership_status', 'organization')
    search_fields = ('full_name', 'member_code', 'email')
