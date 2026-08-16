"""
Auditor Verification Portal — API Views
(doc: 19-Audit-Compliance.md)

Three read-only endpoints that allow auditors and observers to independently
verify election integrity using cryptographic hashes.

Accessible to: org_admin, election_officer, observer (all read-only)
"""
import json
import hashlib
from django.http import HttpResponse
from django.utils import timezone
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from apps.core.permissions import BelongsToOrganization
from apps.elections.models import Election, ElectionState
from apps.voting.models import Vote, VoterRoll
from apps.audit.models import AuditLog


def _get_election_for_audit(election_id, organization):
    """Helper — fetch election scoped to the user's org."""
    try:
        return Election.objects.select_related('organization').get(
            id=election_id,
            organization=organization,
        )
    except Election.DoesNotExist:
        return None


class AuditExportView(APIView):
    """
    GET /v1/elections/{election_id}/audit/export/
    Download the complete audit package as JSON.
    Contains: election metadata, state history, anonymized ballot hashes,
    participation stats, and the audit log.
    Does NOT contain: voter identities or actual ballot selections.
    """
    permission_classes = [IsAuthenticated, BelongsToOrganization]

    def get(self, request, election_id):
        election = _get_election_for_audit(election_id, request.user.organization)
        if not election:
            return Response({'error': 'Election not found.'}, status=status.HTTP_404_NOT_FOUND)

        # --- Votes (anonymized — only hashes, no ballot_data) ---
        votes = Vote.objects.filter(election=election).values(
            'receipt_hash', 'weight', 'created_at'
        )

        # --- Participation stats ---
        voter_roll = VoterRoll.objects.filter(election=election)
        total_eligible = voter_roll.count()
        total_voted = voter_roll.filter(has_voted=True).count()

        # --- State transition history ---
        transitions = election.state_transitions.all().order_by('created_at').values(
            'from_state', 'to_state', 'created_at', 'triggered_by__email'
        )

        # --- Audit log entries for this election ---
        audit_entries = AuditLog.objects.filter(
            organization=election.organization,
            target_id=election.id,
        ).order_by('created_at').values(
            'action', 'created_at', 'ip_address', 'actor__email', 'metadata'
        )

        package = {
            'generated_at': timezone.now().isoformat(),
            'generator': 'EMS Auditor Verification Portal v1.0',
            'election': {
                'id': str(election.id),
                'title': election.title,
                'organization': election.organization.name,
                'state': election.state,
                'ballot_snapshot_hash': election.ballot_snapshot_hash or '(not generated)',
                'is_secret_ballot': election.is_secret_ballot,
                'voting_start_at': election.voting_start_at.isoformat() if election.voting_start_at else None,
                'voting_end_at': election.voting_end_at.isoformat() if election.voting_end_at else None,
            },
            'participation': {
                'total_eligible_voters': total_eligible,
                'total_ballots_cast': total_voted,
                'turnout_percent': round((total_voted / total_eligible * 100), 2) if total_eligible else 0,
                'total_vote_records': votes.count(),
            },
            'integrity': {
                'note': 'The receipt_hash for each ballot is a SHA-256 of the ballot contents + a random salt. '
                        'It uniquely identifies a vote without revealing its contents.',
                'anonymized_ballots': [
                    {
                        'receipt_hash': v['receipt_hash'],
                        'weight': str(v['weight']),
                        'cast_at': v['created_at'].isoformat(),
                    }
                    for v in votes
                ],
            },
            'state_history': [
                {
                    'from_state': t['from_state'],
                    'to_state': t['to_state'],
                    'at': t['created_at'].isoformat(),
                    'triggered_by': t['triggered_by__email'] or '🤖 Celery (automatic)',
                }
                for t in transitions
            ],
            'audit_log': [
                {
                    'action': e['action'],
                    'at': e['created_at'].isoformat(),
                    'by': e['actor__email'] or 'system',
                    'ip': e['ip_address'],
                    'metadata': e['metadata'],
                }
                for e in audit_entries
            ],
        }

        # Compute a master hash of this entire package for tamper detection
        package_json = json.dumps(package, sort_keys=True, default=str)
        package['package_integrity_hash'] = hashlib.sha256(package_json.encode()).hexdigest()

        # Return as downloadable JSON file
        response = HttpResponse(
            json.dumps(package, indent=2, default=str),
            content_type='application/json',
        )
        safe_title = ''.join(c if c.isalnum() else '_' for c in election.title)
        response['Content-Disposition'] = f'attachment; filename="audit_{safe_title}.json"'
        return response


class AuditVerifyHashView(APIView):
    """
    GET /v1/elections/{election_id}/audit/verify-hash/
    Recomputes a live integrity check and returns:
    - The stored ballot_snapshot_hash from the DB
    - A live recomputed hash of all vote receipt hashes
    - Whether they are consistent
    """
    permission_classes = [IsAuthenticated, BelongsToOrganization]

    def get(self, request, election_id):
        election = _get_election_for_audit(election_id, request.user.organization)
        if not election:
            return Response({'error': 'Election not found.'}, status=status.HTTP_404_NOT_FOUND)

        # Compute a live Merkle-style hash of all vote receipt hashes
        receipt_hashes = list(
            Vote.objects.filter(election=election)
            .order_by('created_at')
            .values_list('receipt_hash', flat=True)
        )

        combined = ''.join(receipt_hashes)
        live_votes_hash = hashlib.sha256(combined.encode()).hexdigest() if receipt_hashes else 'no_votes'

        total_votes = len(receipt_hashes)

        voter_roll = VoterRoll.objects.filter(election=election)
        total_eligible = voter_roll.count()
        total_voted = voter_roll.filter(has_voted=True).count()

        # Consistency check: vote records should match has_voted count
        counts_consistent = (total_votes == total_voted)

        return Response({
            'election_id': str(election.id),
            'election_title': election.title,
            'ballot_snapshot_hash': election.ballot_snapshot_hash or None,
            'live_votes_hash': live_votes_hash,
            'total_eligible_voters': total_eligible,
            'total_ballots_cast': total_voted,
            'total_vote_records_in_db': total_votes,
            'counts_are_consistent': counts_consistent,
            'verified_at': timezone.now().isoformat(),
        })


class AuditReceiptLookupView(APIView):
    """
    GET /v1/elections/{election_id}/audit/receipt/{hash}/
    Checks if a specific vote receipt hash exists in the database.
    Used by individual voters to verify their ballot was counted.
    Returns only existence — never reveals ballot content.
    """
    permission_classes = [IsAuthenticated, BelongsToOrganization]

    def get(self, request, election_id, receipt_hash):
        election = _get_election_for_audit(election_id, request.user.organization)
        if not election:
            return Response({'error': 'Election not found.'}, status=status.HTTP_404_NOT_FOUND)

        # Sanitize the hash
        receipt_hash = receipt_hash.strip().lower()
        if len(receipt_hash) != 64:
            return Response({'error': 'Invalid receipt hash format. Must be 64 hex characters.'}, status=400)

        exists = Vote.objects.filter(election=election, receipt_hash=receipt_hash).exists()

        return Response({
            'receipt_hash': receipt_hash,
            'found': exists,
            'message': (
                '✅ Your vote receipt was found. Your ballot has been recorded and counted.'
                if exists else
                '❌ Receipt not found in this election. Please check the hash and try again.'
            ),
            'election_title': election.title,
            'checked_at': timezone.now().isoformat(),
        })


class AuditLogsView(APIView):
    """
    GET /v1/elections/{election_id}/audit/logs/
    Returns real-time forensic audit log entries for this election.
    """
    permission_classes = [IsAuthenticated, BelongsToOrganization]

    def get(self, request, election_id):
        election = _get_election_for_audit(election_id, request.user.organization)
        if not election:
            return Response({'error': 'Election not found.'}, status=status.HTTP_404_NOT_FOUND)

        logs = AuditLog.objects.filter(
            organization=election.organization,
            target_id=election.id,
        ).order_by('-created_at')[:100]

        data = [
            {
                'id': str(log.id),
                'action': log.action,
                'actor_email': log.actor.email if log.actor else 'system',
                'ip_address': log.ip_address or '-',
                'metadata': log.metadata or {},
                'created_at': log.created_at.isoformat(),
            }
            for log in logs
        ]
        return Response({'results': data, 'count': len(data)})
