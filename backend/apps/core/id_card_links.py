"""
Signed, short-lived links for the printable ID card pages.

The card pages open in a new browser tab, so they cannot carry the JWT
Authorization header. Instead an authenticated user asks for a link
(POST /v1/elections/<id>/id-card-link/) and gets the card URL with a signed
token that is only valid for that card (or bulk sheet) for a few minutes.
"""
from django.core import signing
from django.http import HttpResponse
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

SALT = 'ems.id-card-link'
MAX_AGE_SECONDS = 10 * 60

KINDS = {'candidate', 'voter'}
REVIEWER_ROLES = {'org_admin', 'election_officer', 'super_admin'}


def is_reviewer(user, election):
    if not user or not user.is_authenticated:
        return False
    if user.role == 'super_admin':
        return True
    in_org = user.organization_id == election.organization_id
    return in_org and (user.role in REVIEWER_ROLES or getattr(user, 'is_org_admin', False))


def make_token(kind, election_id, target):
    """target is the candidate/voter-roll id, or 'bulk'."""
    return signing.dumps({'k': kind, 'e': str(election_id), 't': str(target)}, salt=SALT)


def token_allows(request, kind, election_id, target):
    token = request.query_params.get('t') or request.GET.get('t')
    if not token:
        return False
    try:
        data = signing.loads(token, salt=SALT, max_age=MAX_AGE_SECONDS)
    except signing.BadSignature:
        return False
    return data == {'k': kind, 'e': str(election_id), 't': str(target)}


def denied_response():
    return HttpResponse(
        '<!doctype html><meta charset="utf-8"><title>Link expired</title>'
        '<body style="font-family:system-ui,sans-serif;padding:48px;text-align:center;color:#334155">'
        '<h2>This ID card link has expired or is not valid.</h2>'
        '<p>Open the ID card again from the Election app.</p></body>',
        status=403,
    )


class IdCardLinkView(APIView):
    """
    POST /v1/elections/<election_id>/id-card-link/
    Body: {"kind": "candidate" | "voter", "id": "<candidate or voter-roll id>" | "bulk"}
    Returns {"url": "/v1/elections/.../id_card/?t=<token>"} valid for 10 minutes.

    Reviewers (org admin, election officer, super admin) get any card or bulk
    sheet in their organization; a candidate or voter only their own card.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, election_id):
        from django.shortcuts import get_object_or_404
        from apps.elections.models import Election
        from apps.candidates.models import Candidate, is_own_nomination
        from apps.voting.models import VoterRoll

        kind = request.data.get('kind')
        target = str(request.data.get('id') or '')
        if kind not in KINDS or not target:
            return Response({'detail': "kind must be 'candidate' or 'voter' and id is required."},
                            status=status.HTTP_400_BAD_REQUEST)

        election = get_object_or_404(Election, id=election_id)
        user = request.user
        reviewer = is_reviewer(user, election)
        plural = 'candidates' if kind == 'candidate' else 'voters'

        if target == 'bulk':
            if not reviewer:
                return Response({'detail': 'Only election officials can print all ID cards.'},
                                status=status.HTTP_403_FORBIDDEN)
            path = f'/v1/elections/{election.id}/{plural}/id_cards_bulk/'
        else:
            if kind == 'candidate':
                obj = get_object_or_404(Candidate, id=target, election=election)
                own = is_own_nomination(user, obj.email, obj.contact_number)
            else:
                obj = get_object_or_404(VoterRoll, id=target, election=election)
                own = bool(
                    (user.email and obj.email and obj.email.strip().lower() == user.email.strip().lower())
                    or (user.phone and obj.phone and obj.phone.strip() == user.phone.strip())
                )
            if not (reviewer or own):
                return Response({'detail': 'You can only open your own ID card.'},
                                status=status.HTTP_403_FORBIDDEN)
            path = f'/v1/elections/{election.id}/{plural}/{obj.id}/id_card/'
            target = str(obj.id)

        token = make_token(kind, election.id, target)
        return Response({'url': f'{path}?t={token}', 'expires_in': MAX_AGE_SECONDS})
