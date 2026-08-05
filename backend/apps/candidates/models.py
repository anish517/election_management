"""
Candidate and Nomination Models
(doc: 08-Database-Design.md §8.2 candidates, nominations tables)
(doc: 14-Candidate-Management.md)
"""
import uuid
from django.db import models
from apps.core.models import TimestampedModel


class NominationStatus(models.TextChoices):
    DRAFT = 'draft', 'Draft'
    SUBMITTED = 'submitted', 'Submitted'
    UNDER_REVIEW = 'under_review', 'Under Review'
    APPROVED = 'approved', 'Approved'
    REJECTED = 'rejected', 'Rejected'
    WITHDRAWN = 'withdrawn', 'Withdrawn'


class Candidate(TimestampedModel):
    """
    A member running for a position.
    (doc: 08-Database-Design.md §8.2 candidates table)
    """
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, related_name='candidates'
    )
    position = models.ForeignKey(
        'elections.Position', on_delete=models.CASCADE, related_name='candidates'
    )
    member = models.ForeignKey(
        'members.Member', on_delete=models.CASCADE, related_name='candidacies'
    )
    
    # Nomination details (doc: 14-Candidate-Management.md §14.2)
    manifesto = models.TextField(blank=True, default='')
    status = models.CharField(
        max_length=20, choices=NominationStatus.choices, default=NominationStatus.DRAFT
    )
    
    # Audit trail for approval
    reviewed_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True, blank=True,
        related_name='nominations_reviewed'
    )
    review_notes = models.TextField(blank=True, default='')
    reviewed_at = models.DateTimeField(null=True, blank=True)
    
    # Support for team/slate voting (future feature, but good to have column ready)
    slate_name = models.CharField(max_length=100, blank=True, default='')

    class Meta:
        db_table = 'candidates'
        unique_together = [['election', 'position', 'member']]
        
    def __str__(self):
        return f"{self.member.full_name} for {self.position.title} ({self.status})"


class CandidateDocument(models.Model):
    """
    Supporting documents for a nomination.
    (doc: 14-Candidate-Management.md §14.2)
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    candidate = models.ForeignKey(
        Candidate, on_delete=models.CASCADE, related_name='documents'
    )
    document_type = models.CharField(max_length=50) # e.g. 'citizenship', 'tax_clearance'
    file_url = models.URLField()
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'candidate_documents'
