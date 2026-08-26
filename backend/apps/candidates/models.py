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
    A standalone candidate running for a position in an election.
    """
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, related_name='candidates'
    )
    position = models.ForeignKey(
        'elections.Position', on_delete=models.CASCADE, related_name='candidates'
    )
    quota = models.ForeignKey(
        'elections.PositionQuota', on_delete=models.SET_NULL, null=True, blank=True, related_name='candidates'
    )
    quota_name = models.CharField(max_length=100, blank=True, default='')
    
    # Candidate Profile (Rich Data)
    first_name = models.CharField(max_length=100, blank=True, default='')
    middle_name = models.CharField(max_length=100, blank=True, default='')
    last_name = models.CharField(max_length=100, blank=True, default='')
    email = models.EmailField(blank=True, default='')
    contact_number = models.CharField(max_length=20, blank=True, default='')
    gender = models.CharField(max_length=20, blank=True, default='')
    date_of_birth = models.DateField(null=True, blank=True)
    address = models.TextField(blank=True, default='')
    
    candidate_image = models.URLField(blank=True, default='')
    candidate_signature = models.URLField(blank=True, default='')
    personal_description = models.TextField(blank=True, default='')
    contribution_to_org = models.TextField(blank=True, default='')

    # Nomination details
    manifesto = models.TextField(blank=True, default='')
    status = models.CharField(
        max_length=20, choices=NominationStatus.choices, default=NominationStatus.DRAFT
    )
    payment_status = models.CharField(
        max_length=30,
        choices=[
            ('unpaid', 'Unpaid'),
            ('pending_verification', 'Pending Verification'),
            ('paid', 'Paid / Verified'),
            ('waived', 'Waived / Free'),
        ],
        default='unpaid',
        db_index=True,
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
        # unique_together removed since member is removed
        
    def __str__(self):
        return f"{self.first_name} {self.last_name} for {self.position.title} ({self.status})"

    @property
    def full_name(self):
        parts = [self.first_name, self.middle_name, self.last_name]
        return " ".join([p for p in parts if p])


class CandidateEndorsement(TimestampedModel):
    """
    Proposers and Supporters for a candidate.
    """
    candidate = models.ForeignKey(
        Candidate, on_delete=models.CASCADE, related_name='endorsements'
    )
    endorsement_type = models.CharField(
        max_length=20, choices=[('proposer', 'Proposer'), ('supporter', 'Supporter')]
    )
    name = models.CharField(max_length=255)
    citizenship_number = models.CharField(max_length=100, blank=True, default='')
    phone = models.CharField(max_length=20, blank=True, default='')
    membership_id = models.CharField(max_length=100, blank=True, default='')
    signature_url = models.URLField(blank=True, default='')

    class Meta:
        db_table = 'candidate_endorsements'
        ordering = ['created_at']

    def __str__(self):
        return f"{self.endorsement_type.capitalize()}: {self.name} for {self.candidate.first_name}"


class CandidateObjectionStatus(models.TextChoices):
    PENDING = 'pending', 'Pending Review'
    UPHELD = 'upheld', 'Upheld (Objection Accepted)'
    DISMISSED = 'dismissed', 'Dismissed (Candidate Cleared)'


class CandidateObjection(TimestampedModel):
    """
    Formal objections filed against candidate eligibility during candidacy claim period.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, related_name='candidate_objections'
    )
    candidate = models.ForeignKey(
        Candidate, on_delete=models.CASCADE, related_name='objections'
    )
    claimant_name = models.CharField(max_length=255)
    claimant_email = models.EmailField(max_length=255)
    claimant_phone = models.CharField(max_length=50, blank=True, default='')
    claimant_citizenship_number = models.CharField(max_length=100, blank=True, default='')
    
    objection_reason = models.TextField()
    evidence_file = models.FileField(upload_to='candidate_objections/', null=True, blank=True)

    status = models.CharField(
        max_length=20, choices=CandidateObjectionStatus.choices, default=CandidateObjectionStatus.PENDING, db_index=True
    )
    resolution_notes = models.TextField(blank=True, default='')
    resolved_by = models.ForeignKey(
        'users.User', on_delete=models.SET_NULL, null=True, blank=True, related_name='resolved_candidate_objections'
    )
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'candidate_objections'
        ordering = ['-created_at']

    def __str__(self):
        return f"Objection against {self.candidate.full_name} by {self.claimant_name} ({self.status})"


class CandidateDocument(models.Model):
    """
    Supporting documents for a nomination.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    candidate = models.ForeignKey(
        Candidate, on_delete=models.CASCADE, related_name='documents'
    )
    document_type = models.CharField(max_length=50)
    file_url = models.URLField()
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'candidate_documents'
