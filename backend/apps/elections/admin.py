from django.contrib import admin
from apps.elections.models import Election, Position, ElectionStateTransition, ElectionRoleAssignment

class PositionInline(admin.TabularInline):
    model = Position
    extra = 1

@admin.register(Election)
class ElectionAdmin(admin.ModelAdmin):
    list_display = ('title', 'organization', 'state', 'created_at')
    list_filter = ('state', 'organization')
    inlines = [PositionInline]

@admin.register(ElectionStateTransition)
class ElectionStateTransitionAdmin(admin.ModelAdmin):
    list_display = ('election', 'from_state', 'to_state', 'created_at')

@admin.register(ElectionRoleAssignment)
class ElectionRoleAssignmentAdmin(admin.ModelAdmin):
    list_display = ('election', 'user', 'role')
