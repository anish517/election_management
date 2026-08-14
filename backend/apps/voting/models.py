"""
Voting Engine Models (Anonymized)
(doc: 08-Database-Design.md §8.2 voter_rolls, votes, voting_sessions tables)
(doc: 15-Voting-Engine.md §15.2 Anonymization Architecture)

CRITICAL SECURITY CONSTRAINT:
The `votes` table must NEVER have a foreign key to `users`, `members`, or `voter_rolls`.
The `has_voted` flag is stored in `voter_rolls`.
"""
import uuid
import secrets
from django.db import models
from django.utils import timezone
from datetime import timedelta
from apps.core.models import TimestampedModel


class VoterRoll(TimestampedModel):
    """
    A standalone voter eligible to vote in a specific election.
    """
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, related_name='voter_roll'
    )
    
    # Voter Identity
    voter_id = models.CharField(max_length=50, blank=True, default='')
    prefix = models.CharField(max_length=20, blank=True, default='')
    first_name = models.CharField(max_length=100, blank=True, default='')
    middle_name = models.CharField(max_length=100, blank=True, default='')
    last_name = models.CharField(max_length=100, blank=True, default='')
    email = models.EmailField(blank=True, default='')
    phone = models.CharField(max_length=20, blank=True, default='')
    council_number = models.CharField(max_length=100, blank=True, default='')
    citizenship_number = models.CharField(max_length=100, blank=True, default='')
    
    # State flags
    is_eligible = models.BooleanField(default=True)
    ineligibility_reason = models.CharField(max_length=255, blank=True, default='')
    
    has_voted = models.BooleanField(default=False)
    voted_at = models.DateTimeField(null=True, blank=True)
    
    voted_ip_address = models.GenericIPAddressField(null=True, blank=True)
    voted_mac_address = models.CharField(max_length=255, blank=True, default='')
    
    class Meta:
        db_table = 'voter_rolls'
        indexes = [
            models.Index(fields=['election', 'has_voted']),
        ]

    def __str__(self):
        return f"{self.first_name} {self.last_name} - {self.election.title} (Voted: {self.has_voted})"

    @property
    def full_name(self):
        parts = [self.prefix, self.first_name, self.middle_name, self.last_name]
        return " ".join([p for p in parts if p])


class VotingSession(models.Model):
    """
    Short-lived token (15 mins) used to cast a ballot.
    Provides idempotency and prevents double-voting during network flakes.
    (doc: 09-Authentication-Security.md §9.5, 15-Voting-Engine.md §15.3)
    """
    token = models.CharField(max_length=64, primary_key=True, default=secrets.token_urlsafe)
    voter_roll = models.OneToOneField(
        VoterRoll, on_delete=models.CASCADE, related_name='active_session'
    )
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'voting_sessions'
        
    def is_valid(self):
        return not self.is_used and timezone.now() < self.expires_at


class Vote(TimestampedModel):
    """
    The anonymized ballot.
    NO LINK to VoterRoll or Member!
    (doc: 15-Voting-Engine.md §15.2)
    """
    election = models.ForeignKey(
        'elections.Election', on_delete=models.CASCADE, related_name='votes'
    )
    # The actual selections. 
    # Format depends on voting method, but generally:
    # { "position_id_1": ["candidate_id_A", "candidate_id_B"], "position_id_2": ["candidate_id_C"] }
    # Or for ranked choice:
    # { "position_id_1": [{"candidate_id": "X", "rank": 1}, ...] }
    ballot_data = models.JSONField()
    
    # Cryptographic hash of the ballot data + salt for integrity checks (future v2.0)
    receipt_hash = models.CharField(max_length=64, unique=True)
    
    # Track the voting weight for this specific ballot (from member.voting_weight)
    # We copy it here so we don't have to join back to the member (which would break anonymity)
    weight = models.DecimalField(max_digits=10, decimal_places=4, default=1.0)
    
    class Meta:
        db_table = 'votes'
        # No updates/deletes allowed at DB level in production

    def __str__(self):
        return f"Vote {self.receipt_hash[:8]} for {self.election.title}"
