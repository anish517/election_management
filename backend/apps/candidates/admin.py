from django.contrib import admin
from apps.candidates.models import Candidate, CandidateDocument

class CandidateDocumentInline(admin.TabularInline):
    model = CandidateDocument
    extra = 0

@admin.register(Candidate)
class CandidateAdmin(admin.ModelAdmin):
    list_display = ('member', 'election', 'position', 'status')
    list_filter = ('status', 'election')
    inlines = [CandidateDocumentInline]
