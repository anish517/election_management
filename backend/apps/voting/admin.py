from django.contrib import admin
from apps.voting.models import VoterRoll, VotingSession, Vote

@admin.register(VoterRoll)
class VoterRollAdmin(admin.ModelAdmin):
    list_display = ('voter_id', 'first_name', 'last_name', 'election', 'is_eligible', 'has_voted')
    list_filter = ('election', 'is_eligible', 'has_voted')
    search_fields = ('voter_id', 'first_name', 'last_name', 'email')

@admin.register(VotingSession)
class VotingSessionAdmin(admin.ModelAdmin):
    list_display = ('voter_roll', 'is_used', 'expires_at')

@admin.register(Vote)
class VoteAdmin(admin.ModelAdmin):
    list_display = ('receipt_hash', 'election', 'created_at')
    list_filter = ('election',)
    
    # Strictly read-only to preserve integrity
    def has_add_permission(self, request):
        return False
    def has_change_permission(self, request, obj=None):
        return False
    def has_delete_permission(self, request, obj=None):
        return False
