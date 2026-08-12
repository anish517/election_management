from django.contrib import admin
from apps.candidates.models import Candidate, CandidateDocument

class CandidateDocumentInline(admin.TabularInline):
    model = CandidateDocument
    extra = 0

@admin.register(Candidate)
class CandidateAdmin(admin.ModelAdmin):
    list_display = ('first_name', 'last_name', 'election', 'position', 'status', 'created_at')
    list_filter = ('election', 'position', 'status')
    search_fields = ('first_name', 'last_name', 'email')
    inlines = [CandidateDocumentInline]
