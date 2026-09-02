from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone

from apps.elections.models import Election
from apps.voting.models import VoterRoll
from apps.voting.serializers import CastVoteSerializer
from apps.voting.services import BallotService
from apps.users.views import get_client_ip
from apps.audit.models import log_action

class VotingViewSet(viewsets.ViewSet):
    """
    Handles ballot generation, session creation, and secure vote casting.
    """
    permission_classes = [IsAuthenticated]

    def _get_voter_roll(self, request, election_pk):
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
            user_email = request.user.email.strip().lower() if request.user.email else ''
            user_phone = (getattr(request.user, 'phone', None) or '').strip()

            from django.db.models import Q
            qs = VoterRoll.objects.filter(election=election)
            
            filter_q = Q()
            if user_email:
                filter_q |= Q(email__iexact=user_email)
            if user_phone:
                filter_q |= Q(phone=user_phone)

            if not filter_q:
                return None

            return qs.filter(filter_q).first()
        except Exception:
            return None

    # Roles that are NEVER allowed to cast a ballot
    _NON_VOTER_ROLES = {'org_admin', 'election_officer', 'observer', 'auditor', 'super_admin'}

    @action(detail=False, methods=['get'])
    def ballot(self, request, election_pk=None):
        """Returns the structured ballot with approved candidates."""
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)

        # Check if the user's role is a committee/admin role (not eligible to vote)
        user_role = getattr(request.user, 'role', '')
        if user_role in self._NON_VOTER_ROLES:
            return Response({
                'ballot': [],
                'allow_boycott': False,
                'is_secret_ballot': election.is_secret_ballot,
                'not_eligible': True,
                'not_eligible_reason': f'Your role ({user_role.replace("_", " ").title()}) is not permitted to vote. Only registered voters may cast a ballot.',
                'has_voted': False,
                'voter_info': None,
            })

        # Check if election is configured for in-person venue voting only
        if getattr(election, 'election_method', 'online') == 'venue':
            venue_str = f"at {election.venue_name}" if election.venue_name else "at the physical polling booth station"
            return Response({
                'ballot': [],
                'allow_boycott': False,
                'is_secret_ballot': election.is_secret_ballot,
                'not_eligible': True,
                'not_eligible_reason': f'Remote online voting is disabled for this election. This is a Method 2 (Physical In-Person Venue) election. Please cast your ballot in person {venue_str}.',
                'has_voted': False,
                'voter_info': None,
            })

        # Check voter roll and has_voted status
        roll = self._get_voter_roll(request, election_pk)
        if not roll or not roll.is_eligible:
            return Response({
                'ballot': [],
                'allow_boycott': False,
                'is_secret_ballot': election.is_secret_ballot,
                'not_eligible': True,
                'not_eligible_reason': 'You are not enrolled in the certified voter roll for this election.' if not roll else (roll.ineligibility_reason or 'You are marked as ineligible to vote in this election.'),
                'has_voted': False,
                'voter_info': None,
            })

        # Partial Election Branch Verification (Requirement 7)
        if getattr(election, 'is_partial_election', False) and election.target_branches:
            target_branches_clean = [str(b).strip().lower() for b in election.target_branches if str(b).strip()]
            voter_branch = (roll.branch or '').strip().lower()
            if target_branches_clean and voter_branch not in target_branches_clean:
                branches_str = ", ".join(election.target_branches)
                return Response({
                    'ballot': [],
                    'allow_boycott': False,
                    'is_secret_ballot': election.is_secret_ballot,
                    'not_eligible': True,
                    'not_eligible_reason': f'This is a partial election for [{branches_str}] branches only. Your registered branch is "{roll.branch or "Unassigned"}".',
                    'has_voted': False,
                    'voter_info': None,
                })

        has_voted = roll.has_voted
        voter_id = roll.voter_id
        voter_name = f"{roll.first_name} {roll.last_name}".strip() or request.user.email

        ballot_data = BallotService.generate_ballot(election)
        return Response({
            'ballot': ballot_data,
            'allow_boycott': election.allow_boycott,
            'is_secret_ballot': election.is_secret_ballot,
            'not_eligible': False,
            'has_voted': has_voted,
            'election_type': getattr(election, 'election_type', 'fptp'),
            'enable_party': getattr(election, 'enable_party', True),
            'enable_panel': getattr(election, 'enable_panel', True),
            'enable_symbol': getattr(election, 'enable_symbol', True),
            'enable_candidate_photo': getattr(election, 'enable_candidate_photo', True),
            'is_partial_election': getattr(election, 'is_partial_election', False),
            'total_pr_seats': getattr(election, 'total_pr_seats', 10),
            'pr_threshold_percent': float(getattr(election, 'pr_threshold_percent', 0.00)),
            'pr_allocation_method': getattr(election, 'pr_allocation_method', 'modified_sainte_lague'),
            'voter_info': {
                'voter_id': voter_id,
                'full_name': voter_name,
                'email': request.user.email,
                'branch': roll.branch or '',
            },
        })

    @action(detail=False, methods=['post'])
    def session(self, request, election_pk=None):
        """Generates a voting session token."""
        # Block non-voter roles from ever starting a session
        user_role = getattr(request.user, 'role', '')
        if user_role in self._NON_VOTER_ROLES:
            return Response(
                {'error': f'Your role ({user_role.replace("_", " ").title()}) is not permitted to vote. Committee members and administrators cannot cast ballots.'},
                status=403
            )

        roll = self._get_voter_roll(request, election_pk)
        if not roll:
            return Response({'error': 'You are not eligible to vote in this election.'}, status=403)

        if getattr(roll.election, 'is_partial_election', False) and roll.election.target_branches:
            target_branches_clean = [str(b).strip().lower() for b in roll.election.target_branches if str(b).strip()]
            voter_branch = (roll.branch or '').strip().lower()
            if target_branches_clean and voter_branch not in target_branches_clean:
                branches_str = ", ".join(roll.election.target_branches)
                return Response({
                    'error': f'This is a partial election for [{branches_str}] branches only. Your registered branch is "{roll.branch or "Unassigned"}".'
                }, status=403)

        if getattr(roll.election, 'election_method', 'online') == 'venue':
            return Response(
                {'error': 'Remote in-app voting is disabled for this in-person venue election. Please cast your ballot at the venue polling booth.'},
                status=403
            )

        if roll.has_voted:
            return Response({'error': 'You have already cast your ballot in this election. Each voter may only vote once.'}, status=403)

        if roll.election.state != 'voting_open':
            return Response({'error': 'Voting is not currently active.'}, status=400)

        try:
            token = BallotService.start_session(roll)
            if roll.verification_channel == 'unverified':
                from django.utils import timezone
                ua = request.META.get('HTTP_USER_AGENT', '').lower()
                # If requested via Web Browser (Windows, Mac, Linux, Chrome, Firefox, Edge, Safari)
                if any(k in ua for k in ['windows', 'macintosh', 'linux', 'mozilla', 'chrome', 'safari', 'firefox', 'edge']) and not any(k in ua for k in ['okhttp', 'dart/']):
                    roll.verification_channel = 'web_email'
                else:
                    roll.verification_channel = 'mobile_app'
                roll.verified_at = timezone.now()
                roll.save(update_fields=['verification_channel', 'verified_at'])
            return Response({'session_token': token})
        except ValueError as e:
            return Response({'error': str(e)}, status=400)

    @action(detail=False, methods=['post'])
    def cast(self, request, election_pk=None):
        """Casts the ballot using the session token."""
        session_token = request.data.get('session_token')
        if not session_token:
            return Response({'error': 'session_token is required.'}, status=400)
            
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)
            
        serializer = CastVoteSerializer(data=request.data, context={'election': election})
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)
            
        mac_address = (
            request.data.get('device_identifier')
            or request.data.get('mac_address')
            or request.META.get('HTTP_X_DEVICE_IDENTIFIER', '')
        )
        
        try:
            receipt = BallotService.cast_vote(
                session_token=session_token, 
                ballot_data=serializer.validated_data['ballot_data'],
                ip_address=get_client_ip(request),
                mac_address=mac_address
            )
            
            log_action('vote.casted', request.user.organization, request.user, {
                'election_id': election_pk,
                'receipt_hash': receipt
            })
            
            return Response({'success': True, 'receipt_hash': receipt})
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class VoterRollViewSet(viewsets.ModelViewSet):
    """
    Manage voters for a specific election.
    """
    from apps.voting.serializers import VoterRollSerializer
    serializer_class = VoterRollSerializer

    def get_permissions(self):
        from rest_framework import permissions
        if self.action in ['id_card', 'id_cards_bulk']:
            return [permissions.AllowAny()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        return VoterRoll.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs.get('election_pk')
        )

    def perform_create(self, serializer):
        from apps.elections.models import Election
        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )
        serializer.save(election=election)

    @action(detail=False, methods=['post'])
    def preview_csv(self, request, election_pk=None):
        import csv, io, json
        if 'file' not in request.FILES:
            return Response({'error': 'No file uploaded'}, status=status.HTTP_400_BAD_REQUEST)

        mapping_raw = request.data.get('mapping', '{}')
        try:
            mapping = json.loads(mapping_raw)
        except (json.JSONDecodeError, TypeError):
            mapping = {}

        file = request.FILES['file']
        try:
            decoded_file = file.read().decode('utf-8-sig')
            io_string = io.StringIO(decoded_file)
            reader = csv.DictReader(io_string)
            columns = reader.fieldnames or []

            valid_rows = []
            error_rows = []

            existing_voter_ids = set(
                VoterRoll.objects.filter(election_id=election_pk)
                .exclude(voter_id='')
                .values_list('voter_id', flat=True)
            )
            existing_emails = set(
                VoterRoll.objects.filter(election_id=election_pk)
                .exclude(email='')
                .values_list('email', flat=True)
            )

            for i, row in enumerate(reader, start=2):
                mapped = {}
                for csv_col, db_field in mapping.items():
                    mapped[db_field] = row.get(csv_col, '').strip()
                
                # direct match fallback
                for field in ['voter_id', 'prefix', 'first_name', 'middle_name', 'last_name', 'email', 'phone', 'council_number', 'citizenship_number']:
                    if field not in mapped and field in row:
                        mapped[field] = row.get(field, '').strip()

                v_id = mapped.get('voter_id', '')
                email = mapped.get('email', '')
                first = mapped.get('first_name', '')
                last = mapped.get('last_name', '')

                error = None
                if not first or not last:
                    error = 'First name and Last name are required'
                elif v_id and v_id in existing_voter_ids:
                    error = f'Voter ID "{v_id}" already exists'
                elif email and email in existing_emails:
                    error = f'Email "{email}" already exists'

                if error:
                    error_rows.append({'row': i, 'data': dict(row), 'mapped': mapped, 'error': error})
                else:
                    if v_id: existing_voter_ids.add(v_id)
                    if email: existing_emails.add(email)
                    valid_rows.append({
                        'row': i,
                        'voter_id': v_id,
                        'prefix': mapped.get('prefix', ''),
                        'first_name': first,
                        'middle_name': mapped.get('middle_name', ''),
                        'last_name': last,
                        'email': email,
                        'phone': mapped.get('phone', ''),
                        'council_number': mapped.get('council_number', ''),
                        'citizenship_number': mapped.get('citizenship_number', ''),
                    })

            return Response({
                'columns': columns,
                'valid_count': len(valid_rows),
                'error_count': len(error_rows),
                'valid_rows': valid_rows,
                'error_rows': error_rows,
            })
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=False, methods=['post'])
    def import_csv(self, request, election_pk=None):
        import csv, io, json
        from apps.elections.models import Election
        if 'file' not in request.FILES:
            return Response({'error': 'No file uploaded'}, status=status.HTTP_400_BAD_REQUEST)

        mapping_raw = request.data.get('mapping', '{}')
        try:
            mapping = json.loads(mapping_raw)
        except (json.JSONDecodeError, TypeError):
            mapping = {}
            
        election = Election.objects.get(id=election_pk, organization=request.user.organization)

        file = request.FILES['file']
        try:
            decoded_file = file.read().decode('utf-8-sig')
            io_string = io.StringIO(decoded_file)
            reader = csv.DictReader(io_string)

            existing_voter_ids = set(VoterRoll.objects.filter(election=election).exclude(voter_id='').values_list('voter_id', flat=True))
            existing_emails = set(VoterRoll.objects.filter(election=election).exclude(email='').values_list('email', flat=True))

            imported = 0
            skipped = 0
            for row in reader:
                mapped = {}
                for csv_col, db_field in mapping.items():
                    mapped[db_field] = row.get(csv_col, '').strip()
                for field in ['voter_id', 'prefix', 'first_name', 'middle_name', 'last_name', 'email', 'phone', 'council_number', 'citizenship_number']:
                    if field not in mapped and field in row: mapped[field] = row.get(field, '').strip()

                v_id = mapped.get('voter_id', '')
                email = mapped.get('email', '')
                first = mapped.get('first_name', '')
                last = mapped.get('last_name', '')

                if not first or not last or (v_id and v_id in existing_voter_ids) or (email and email in existing_emails):
                    skipped += 1
                    continue

                if v_id: existing_voter_ids.add(v_id)
                if email: existing_emails.add(email)
                
                VoterRoll.objects.create(
                    election=election,
                    voter_id=v_id,
                    prefix=mapped.get('prefix', ''),
                    first_name=first,
                    middle_name=mapped.get('middle_name', ''),
                    last_name=last,
                    email=email,
                    phone=mapped.get('phone', ''),
                    council_number=mapped.get('council_number', ''),
                    citizenship_number=mapped.get('citizenship_number', ''),
                )
                imported += 1

            return Response({'imported': imported, 'skipped': skipped})
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=False, methods=['get'])
    def export_csv(self, request, election_pk=None):
        import csv
        from django.http import HttpResponse
        voters = VoterRoll.objects.filter(election_id=election_pk).order_by('voter_id')
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="voters_export.csv"'
        writer = csv.writer(response)
        writer.writerow([
            'Voter ID', 'Prefix', 'First Name', 'Middle Name', 'Last Name',
            'Email', 'Phone', 'Council Number', 'Citizenship Number', 'Eligible',
            'Verification Channel', 'Verified At', 'Has Voted', 'Voted At'
        ])
        for v in voters:
            writer.writerow([
                v.voter_id, v.prefix, v.first_name, v.middle_name, v.last_name,
                v.email, v.phone, v.council_number, v.citizenship_number, v.is_eligible,
                v.get_verification_channel_display() if hasattr(v, 'get_verification_channel_display') else v.verification_channel,
                v.verified_at.isoformat() if v.verified_at else '',
                'Yes' if v.has_voted else 'No',
                v.voted_at.isoformat() if v.voted_at else ''
            ])
        return response

    @action(detail=False, methods=['post'])
    def import_members(self, request, election_pk=None):
        """
        Import organization roster members directly into the election's VoterRoll via API.
        Optionally accepts 'member_ids' list. If omitted or empty, imports all active,
        eligible members belonging to the organization.
        """
        from apps.elections.models import Election
        from apps.members.models import Member

        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=status.HTTP_404_NOT_FOUND)

        member_ids = request.data.get('member_ids')
        qs = Member.objects.filter(organization=request.user.organization, deleted_at__isnull=True)

        if member_ids and isinstance(member_ids, list) and len(member_ids) > 0:
            qs = qs.filter(id__in=member_ids)
        else:
            # Default to active members
            qs = qs.filter(membership_status='active')

        existing_emails = set(
            VoterRoll.objects.filter(election=election)
            .exclude(email='')
            .values_list('email', flat=True)
        )
        existing_voter_ids = set(
            VoterRoll.objects.filter(election=election)
            .exclude(voter_id='')
            .values_list('voter_id', flat=True)
        )

        imported = 0
        skipped = 0

        for m in qs:
            v_id = m.member_code.strip() if m.member_code else str(m.id)[:8]
            email = m.email.strip().lower() if m.email else ''

            if (email and email in existing_emails) or (v_id and v_id in existing_voter_ids):
                skipped += 1
                continue

            first_name = m.first_name.strip() or (m.full_name.split()[0] if m.full_name else 'Member')
            last_name = m.last_name.strip() or (m.full_name.split()[-1] if len(m.full_name.split()) > 1 else '')

            VoterRoll.objects.create(
                election=election,
                voter_id=v_id,
                prefix=m.prefix,
                first_name=first_name,
                middle_name=m.middle_name,
                last_name=last_name,
                email=email,
                phone=m.phone,
                council_number=m.council_number,
                citizenship_number=m.citizenship_number,
                is_eligible=m.is_eligible_to_vote,
            )

            if email:
                existing_emails.add(email)
            if v_id:
                existing_voter_ids.add(v_id)

            imported += 1

        return Response({
            'message': f'Successfully imported {imported} member(s) into voter roll. Skipped {skipped} already existing.',
            'imported': imported,
            'skipped': skipped,
            'total_processed': qs.count(),
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post'])
    def import_external_api(self, request, election_pk=None):
        """
        Fetch members/voters from an external API URL and preview or import
        them directly into the election's VoterRoll.
        """
        import requests
        import uuid
        from apps.elections.models import Election

        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=status.HTTP_404_NOT_FOUND)

        url = str(request.data.get('url', '')).strip()
        if not url:
            return Response({'error': 'API Endpoint URL is required.'}, status=status.HTTP_400_BAD_REQUEST)

        headers = {'User-Agent': 'ElectionManagementSystem/1.0', 'Accept': 'application/json'}
        auth_header = str(request.data.get('auth_header', '')).strip()
        if auth_header:
            headers['Authorization'] = auth_header
            
        custom_header_name = str(request.data.get('custom_header_name', '')).strip()
        custom_header_val = str(request.data.get('custom_header_value', '')).strip()
        if custom_header_name and custom_header_val:
            headers[custom_header_name] = custom_header_val

        preview_only = bool(request.data.get('preview_only', False))
        mapping = request.data.get('mapping', {})
        if not isinstance(mapping, dict):
            mapping = {}

        try:
            res = requests.get(url, headers=headers, timeout=15)
            res.raise_for_status()
            data = res.json()
        except requests.exceptions.Timeout:
            return Response({'error': 'Connection to external API timed out (15s limit).'}, status=status.HTTP_400_BAD_REQUEST)
        except requests.exceptions.RequestException as e:
            return Response({'error': f'External API request failed: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)
        except ValueError:
            return Response({'error': 'External API returned non-JSON response.'}, status=status.HTTP_400_BAD_REQUEST)

        raw_items = []
        if isinstance(data, list):
            raw_items = data
        elif isinstance(data, dict):
            for key in ['data', 'results', 'members', 'voters', 'users', 'items']:
                if key in data and isinstance(data[key], list):
                    raw_items = data[key]
                    break
            if not raw_items:
                raw_items = [data]

        if not raw_items:
            return Response({'error': 'No voter/member records found in external API response.'}, status=status.HTTP_400_BAD_REQUEST)

        existing_emails = set(
            VoterRoll.objects.filter(election=election)
            .exclude(email='')
            .values_list('email', flat=True)
        )
        existing_voter_ids = set(
            VoterRoll.objects.filter(election=election)
            .exclude(voter_id='')
            .values_list('voter_id', flat=True)
        )

        parsed_records = []
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            v_id = str(item.get(mapping.get('voter_id', 'voter_id')) or item.get('id') or item.get('member_code') or item.get('member_id') or '').strip()
            first = str(item.get(mapping.get('first_name', 'first_name')) or item.get('name') or item.get('full_name') or '').strip()
            middle = str(item.get(mapping.get('middle_name', 'middle_name')) or '').strip()
            last = str(item.get(mapping.get('last_name', 'last_name')) or '').strip()
            
            if not last and ' ' in first:
                parts = first.split()
                first = parts[0]
                last = ' '.join(parts[1:])

            email = str(item.get(mapping.get('email', 'email')) or '').strip().lower()
            phone = str(item.get(mapping.get('phone', 'phone')) or item.get('mobile') or item.get('contact') or '').strip()
            citizenship = str(item.get(mapping.get('citizenship_number', 'citizenship_number')) or item.get('citizenship') or '').strip()
            council = str(item.get(mapping.get('council_number', 'council_number')) or '').strip()
            prefix = str(item.get(mapping.get('prefix', 'prefix')) or '').strip()

            parsed_records.append({
                'voter_id': v_id or str(uuid.uuid4())[:8],
                'prefix': prefix,
                'first_name': first or 'Voter',
                'middle_name': middle,
                'last_name': last,
                'email': email,
                'phone': phone,
                'council_number': council,
                'citizenship_number': citizenship,
                'is_eligible': True,
            })

        if preview_only:
            return Response({
                'preview': parsed_records[:25],
                'total_found': len(parsed_records),
                'message': f'Found {len(parsed_records)} record(s) from external API.',
            }, status=status.HTTP_200_OK)

        imported = 0
        skipped = 0

        for r in parsed_records:
            v_id = r['voter_id']
            email = r['email']

            if (email and email in existing_emails) or (v_id and v_id in existing_voter_ids):
                skipped += 1
                continue

            VoterRoll.objects.create(
                election=election,
                voter_id=v_id,
                prefix=r['prefix'],
                first_name=r['first_name'],
                middle_name=r['middle_name'],
                last_name=r['last_name'],
                email=email,
                phone=r['phone'],
                council_number=r['council_number'],
                citizenship_number=r['citizenship_number'],
                is_eligible=True,
            )

            if email:
                existing_emails.add(email)
            if v_id:
                existing_voter_ids.add(v_id)

            imported += 1

        return Response({
            'message': f'Successfully imported {imported} voter(s) from external API. Skipped {skipped} already existing.',
            'imported': imported,
            'skipped': skipped,
            'total_processed': len(parsed_records),
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny], authentication_classes=[])
    def id_card(self, request, election_pk=None, pk=None):
        """
        GET /v1/elections/{election_id}/voters/{voter_id}/id_card/
        Renders a printable, official Digital Voter ID Card (CR80 format, photo-free).
        """
        from django.http import HttpResponse
        from apps.elections.models import Election

        from django.shortcuts import get_object_or_404
        try:
            election = get_object_or_404(Election, id=election_pk)
            voter = get_object_or_404(VoterRoll, pk=pk, election=election)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_404_NOT_FOUND)

        org = election.organization
        org_name = org.name if org else 'Election Management'
        org_logo = election.logo_url or (org.logo_url if org else '')

        qr_data = f"EMS-VOTER:{voter.voter_id}:{election.id}:{voter.email or voter.phone}"
        qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=120x120&data={qr_data}"

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>Voter ID Card - {voter.full_name}</title>
  <style>
    @page {{
      size: 85.6mm 54mm;
      margin: 0;
    }}
    @media print {{
      body {{ margin: 0; padding: 0; background: none; }}
      .no-print {{ display: none !important; }}
      .card-wrap {{ box-shadow: none !important; margin: 0 auto; page-break-after: always; }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, sans-serif;
      background: #F1F5F9;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px;
      margin: 0;
    }}
    .action-bar {{
      margin-bottom: 16px;
      display: flex;
      gap: 12px;
    }}
    .btn {{
      background: #059669;
      color: white;
      border: none;
      padding: 9px 18px;
      border-radius: 6px;
      font-weight: 700;
      cursor: pointer;
      font-size: 13px;
      box-shadow: 0 2px 6px rgba(5,150,105,0.3);
    }}
    .btn:hover {{ background: #047857; }}
    .card-wrap {{
      width: 85.6mm;
      height: 54mm;
      background: #FFFFFF;
      background-image: radial-gradient(circle at 50% 50%, rgba(16, 185, 129, 0.04) 0%, rgba(255,255,255,1) 70%);
      border-radius: 8px;
      box-shadow: 0 6px 20px rgba(0,0,0,0.12);
      border: 1.5px solid #059669;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      padding: 7px 10px;
    }}
    .top-banner {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1.5px solid #059669;
      padding-bottom: 4px;
    }}
    .header-left {{
      display: flex;
      align-items: center;
      gap: 7px;
    }}
    .header-logo {{
      width: 30px;
      height: 30px;
      border-radius: 4px;
      object-fit: contain;
    }}
    .org-title {{
      font-size: 9.5px;
      font-weight: 900;
      color: #065F46;
      line-height: 1.1;
      text-transform: uppercase;
      letter-spacing: 0.2px;
    }}
    .el-title {{
      font-size: 8px;
      font-weight: 700;
      color: #1E293B;
      line-height: 1.1;
    }}
    .badge-ribbon {{
      background: linear-gradient(135deg, #059669, #047857);
      color: #FFFFFF;
      font-size: 7.5px;
      font-weight: 900;
      padding: 2.5px 6px;
      border-radius: 4px;
      letter-spacing: 0.4px;
      text-align: center;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }}
    .card-body {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      flex: 1;
      padding: 4px 0;
    }}
    .elector-info {{
      flex: 1;
    }}
    .elector-name {{
      font-size: 13.5px;
      font-weight: 900;
      color: #0F172A;
      margin-bottom: 3px;
      line-height: 1.2;
    }}
    .voter-id-pill {{
      display: inline-block;
      background: #ECFDF5;
      color: #065F46;
      border: 1px solid #A7F3D0;
      border-radius: 4px;
      font-size: 8.5px;
      font-weight: 800;
      padding: 1.5px 6px;
      margin-bottom: 4px;
    }}
    .meta-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 2px 6px;
      font-size: 7.5px;
      color: #334155;
    }}
    .meta-item {{
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }}
    .meta-label {{
      font-weight: bold;
      color: #64748B;
    }}
    .status-verified {{
      font-size: 7.5px;
      font-weight: 800;
      color: #059669;
      margin-top: 3px;
      display: flex;
      align-items: center;
      gap: 3px;
    }}
    .qr-container {{
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
    }}
    .qr-code {{
      width: 44px;
      height: 44px;
      border: 1px solid #CBD5E1;
      border-radius: 4px;
      padding: 1px;
      background: white;
    }}
    .qr-text {{
      font-size: 6px;
      font-weight: bold;
      color: #64748B;
      margin-top: 2px;
      letter-spacing: 0.3px;
    }}
    .card-footer {{
      border-top: 1px dashed #CBD5E1;
      padding-top: 3px;
      display: flex;
      justify-content: space-between;
      align-items: flex-end;
    }}
    .footer-stamp {{
      font-size: 6.5px;
      color: #64748B;
      font-weight: 600;
      line-height: 1.2;
    }}
    .officer-sign {{
      text-align: right;
      font-size: 6.5px;
      color: #DC2626;
      font-weight: 800;
    }}
    .officer-line {{
      width: 60px;
      border-top: 1px solid #DC2626;
      margin-top: 1px;
    }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <button class="btn" onclick="window.print()">🖨️ Print / Save PDF</button>
    <button class="btn" style="background:#64748B;" onclick="window.close()">Close</button>
  </div>

  <div class="card-wrap">
    <div class="top-banner">
      <div class="header-left">
        {f'<img src="{org_logo}" class="header-logo">' if org_logo else '<div style="font-size:20px;">🏛️</div>'}
        <div>
          <div class="org-title">{org_name}</div>
          <div class="el-title">{election.title}</div>
        </div>
      </div>
      <div class="badge-ribbon">VOTER ID<br><span style="font-size:6px;font-weight:normal;">मतदाता परिचय</span></div>
    </div>

    <div class="card-body">
      <div class="elector-info">
        <div class="elector-name">{voter.full_name}</div>
        <div class="voter-id-pill">मतदाता नं (Voter ID): <b>{voter.voter_id}</b></div>
        <div class="meta-grid">
          {f'<div class="meta-item"><span class="meta-label">Council:</span> {voter.council_number}</div>' if voter.council_number else '<div class="meta-item"><span class="meta-label">Franchise:</span> Certified</div>'}
          {f'<div class="meta-item"><span class="meta-label">Phone:</span> {voter.phone}</div>' if voter.phone else ''}
          {f'<div class="meta-item"><span class="meta-label">Email:</span> {voter.email}</div>' if voter.email else ''}
        </div>
        <div class="status-verified">✓ Statutorily Enrolled & Eligible (योग्य मतदाता)</div>
      </div>

      <div class="qr-container">
        <img src="{qr_url}" class="qr-code" alt="QR">
        <div class="qr-text">EMS VERIFY TOKEN</div>
      </div>
    </div>

    <div class="card-footer">
      <div class="footer-stamp">
        Election Management System • निर्वाचन आयोग
      </div>
      <div class="officer-sign">
        Election Officer (निर्वाचन अधिकृत)
        <div class="officer-line"></div>
      </div>
    </div>
  </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html')

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny], authentication_classes=[])
    def id_cards_bulk(self, request, election_pk=None):
        """
        GET /v1/elections/{election_id}/voters/id_cards_bulk/
        Renders a printable sheet of all certified voter ID cards (photo-free, professional).
        """
        from django.http import HttpResponse
        from apps.elections.models import Election

        from django.shortcuts import get_object_or_404
        try:
            election = get_object_or_404(Election, id=election_pk)
            voters = VoterRoll.objects.filter(election=election, is_eligible=True).order_by('voter_id', 'id')
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_404_NOT_FOUND)

        org = election.organization
        org_name = org.name if org else 'Election Management'
        org_logo = election.logo_url or (org.logo_url if org else '')

        cards_html = ""
        for v in voters:
            qr_data = f"EMS-VOTER:{v.voter_id}:{election.id}:{v.email or v.phone}"
            qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=120x120&data={qr_data}"
            cards_html += f"""
            <div class="card-wrap">
              <div class="top-banner">
                <div class="header-left">
                  {f'<img src="{org_logo}" class="header-logo">' if org_logo else '<div style="font-size:18px;">🏛️</div>'}
                  <div>
                    <div class="org-title">{org_name}</div>
                    <div class="el-title">{election.title}</div>
                  </div>
                </div>
                <div class="badge-ribbon">VOTER ID<br><span style="font-size:5.5px;font-weight:normal;">मतदाता परिचय</span></div>
              </div>

              <div class="card-body">
                <div class="elector-info">
                  <div class="elector-name">{v.full_name}</div>
                  <div class="voter-id-pill">मतदाता नं (Voter ID): <b>{v.voter_id}</b></div>
                  <div class="meta-grid">
                    {f'<div class="meta-item"><span class="meta-label">Council:</span> {v.council_number}</div>' if v.council_number else '<div class="meta-item"><span class="meta-label">Franchise:</span> Certified</div>'}
                    {f'<div class="meta-item"><span class="meta-label">Phone:</span> {v.phone}</div>' if v.phone else ''}
                    {f'<div class="meta-item"><span class="meta-label">Email:</span> {v.email}</div>' if v.email else ''}
                  </div>
                  <div class="status-verified">✓ Statutorily Enrolled & Eligible</div>
                </div>

                <div class="qr-container">
                  <img src="{qr_url}" class="qr-code" alt="QR">
                  <div class="qr-text">EMS VERIFY</div>
                </div>
              </div>

              <div class="card-footer">
                <div class="footer-stamp">Election Management System</div>
                <div class="officer-sign">Election Officer (अधिकृत)<div class="officer-line"></div></div>
              </div>
            </div>
            """

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>Batch Voter ID Cards - {election.title}</title>
  <style>
    @page {{
      size: A4 portrait;
      margin: 10mm;
    }}
    @media print {{
      body {{ margin: 0; padding: 0; background: none; }}
      .no-print {{ display: none !important; }}
      .card-wrap {{ box-shadow: none !important; page-break-inside: avoid; }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, sans-serif;
      background: #F8FAFC;
      padding: 20px;
      margin: 0;
    }}
    .action-bar {{
      margin-bottom: 20px;
      display: flex;
      gap: 12px;
      justify-content: center;
    }}
    .btn {{
      background: #059669;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 6px;
      font-weight: 700;
      cursor: pointer;
      font-size: 14px;
      box-shadow: 0 2px 6px rgba(5,150,105,0.3);
    }}
    .btn:hover {{ background: #047857; }}
    .grid-container {{
      display: grid;
      grid-template-columns: repeat(2, 85.6mm);
      gap: 8mm;
      justify-content: center;
    }}
    .card-wrap {{
      width: 85.6mm;
      height: 54mm;
      background: #FFFFFF;
      background-image: radial-gradient(circle at 50% 50%, rgba(16, 185, 129, 0.04) 0%, rgba(255,255,255,1) 70%);
      border-radius: 8px;
      border: 1.5px solid #059669;
      box-shadow: 0 4px 14px rgba(0,0,0,0.08);
      overflow: hidden;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      padding: 6px 9px;
      page-break-inside: avoid;
    }}
    .top-banner {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1.5px solid #059669;
      padding-bottom: 3px;
    }}
    .header-left {{ display: flex; align-items: center; gap: 6px; }}
    .header-logo {{ width: 26px; height: 26px; border-radius: 4px; object-fit: contain; }}
    .org-title {{ font-size: 9px; font-weight: 900; color: #065F46; line-height: 1.1; text-transform: uppercase; }}
    .el-title {{ font-size: 7.5px; font-weight: 700; color: #1E293B; line-height: 1.1; }}
    .badge-ribbon {{ background: linear-gradient(135deg, #059669, #047857); color: white; font-size: 6.5px; font-weight: 900; padding: 2px 5px; border-radius: 3px; }}
    .card-body {{ display: flex; align-items: center; justify-content: space-between; gap: 6px; flex: 1; padding: 3px 0; }}
    .elector-info {{ flex: 1; }}
    .elector-name {{ font-size: 12px; font-weight: 900; color: #0F172A; margin-bottom: 2px; }}
    .voter-id-pill {{ display: inline-block; background: #ECFDF5; color: #065F46; border: 1px solid #A7F3D0; border-radius: 3px; font-size: 8px; font-weight: 800; padding: 1px 5px; margin-bottom: 3px; }}
    .meta-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 1.5px 4px; font-size: 7px; color: #334155; }}
    .meta-item {{ white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
    .meta-label {{ font-weight: bold; color: #64748B; }}
    .status-verified {{ font-size: 7px; font-weight: 800; color: #059669; margin-top: 2px; }}
    .qr-container {{ display: flex; flex-direction: column; align-items: center; text-align: center; }}
    .qr-code {{ width: 38px; height: 38px; border: 1px solid #CBD5E1; border-radius: 3px; padding: 1px; background: white; }}
    .qr-text {{ font-size: 5.5px; font-weight: bold; color: #64748B; margin-top: 1px; }}
    .card-footer {{ border-top: 1px dashed #CBD5E1; padding-top: 2px; display: flex; justify-content: space-between; align-items: flex-end; }}
    .footer-stamp {{ font-size: 6px; color: #64748B; }}
    .officer-sign {{ text-align: right; font-size: 6px; color: #DC2626; font-weight: 800; }}
    .officer-line {{ width: 50px; border-top: 1px solid #DC2626; margin-top: 1px; }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <button class="btn" onclick="window.print()">🖨️ Print All Cards ({len(voters)} Voters)</button>
  </div>
  <div class="grid-container">
    {cards_html}
  </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html')


class VotingHistoryView(viewsets.ViewSet):
    """
    GET /v1/voting/history/
    Returns all elections the current member has successfully voted in.
    """
    permission_classes = [IsAuthenticated]

    def list(self, request):
        rolls = VoterRoll.objects.filter(email=request.user.email, has_voted=True).select_related('election')
        history = []
        for r in rolls:
            history.append({
                'election_id': str(r.election.id),
                'title': r.election.title,
                'voted_at': r.voted_at,
                'receipt': 'Hidden for MVP' # You can add receipt_hash if we store it on VoterRoll, but we don't.
            })
        return Response(history)


class VoterClaimViewSet(viewsets.ModelViewSet):
    """
    CRUD and review for Voter Roll Claims and Objections.
    """
    permission_classes = [IsAuthenticated]
    from apps.voting.serializers import VoterClaimSerializer
    serializer_class = VoterClaimSerializer

    def get_queryset(self):
        from apps.voting.models import VoterClaim
        election_pk = self.kwargs.get('election_pk')
        user = self.request.user
        qs = VoterClaim.objects.filter(election_id=election_pk, election__organization=user.organization)
        
        is_officer = (
            user.role in ['org_admin', 'election_officer', 'super_admin']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            qs = qs.filter(claimant_email__iexact=user.email.strip().lower())
        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        from django.utils import timezone
        from rest_framework.exceptions import ValidationError, PermissionDenied
        user = self.request.user
        if user.role in ['observer', 'auditor']:
            raise PermissionDenied('Observers and Auditors have read-only monitoring access and cannot file voter claims.')

        election_pk = self.kwargs.get('election_pk')
        election = Election.objects.get(id=election_pk, organization=user.organization)
        now = timezone.now()

        # Schedule Gating
        if election.first_voter_list_date and now < election.first_voter_list_date:
            raise ValidationError({'detail': 'Voter roll claim period has not started yet.'})
        if election.voter_list_claim_date and now > election.voter_list_claim_date:
            raise ValidationError({'detail': 'Voter roll claim deadline has passed.'})

        serializer.save(
            election=election,
            claimant_name=serializer.validated_data.get('claimant_name') or self.request.user.full_name or self.request.user.email,
            claimant_email=serializer.validated_data.get('claimant_email') or self.request.user.email,
        )

    @action(detail=True, methods=['post'])
    def resolve(self, request, election_pk=None, pk=None):
        """
        Election Officer / Org Admin resolves a voter claim (Approve / Reject).
        """
        from apps.elections.permissions import IsElectionOfficer
        from django.utils import timezone
        from apps.voting.serializers import VoterClaimSerializer
        if not IsElectionOfficer().has_permission(request, self):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        claim = self.get_object()
        new_status = request.data.get('status')
        if new_status not in ['approved', 'rejected']:
            return Response({'detail': "Status must be 'approved' or 'rejected'."}, status=status.HTTP_400_BAD_REQUEST)

        notes = request.data.get('resolution_notes', '')
        claim.status = new_status
        claim.resolution_notes = notes
        claim.resolved_by = request.user
        claim.resolved_at = timezone.now()
        claim.save()

        # Automated side effects if approved
        if new_status == 'approved':
            if claim.claim_type == 'omission':
                existing_voter = VoterRoll.objects.filter(election=claim.election, email__iexact=claim.claimant_email).first()
                if not existing_voter and claim.claimant_phone:
                    existing_voter = VoterRoll.objects.filter(election=claim.election, phone=claim.claimant_phone).first()

                if existing_voter:
                    existing_voter.is_eligible = True
                    existing_voter.ineligibility_reason = ''
                    if claim.claimant_citizenship_number and not existing_voter.citizenship_number:
                        existing_voter.citizenship_number = claim.claimant_citizenship_number
                    existing_voter.save()
                else:
                    parts = (claim.claimant_name or '').strip().split()
                    first_name = parts[0] if parts else ''
                    middle_name = " ".join(parts[1:-1]) if len(parts) > 2 else ''
                    last_name = parts[-1] if len(parts) > 1 else ''

                    VoterRoll.objects.create(
                        election=claim.election,
                        first_name=first_name,
                        middle_name=middle_name,
                        last_name=last_name,
                        email=claim.claimant_email,
                        phone=claim.claimant_phone,
                        citizenship_number=claim.claimant_citizenship_number,
                        is_eligible=True,
                    )
            elif claim.claim_type == 'objection' and claim.voter_roll:
                claim.voter_roll.is_eligible = False
                claim.voter_roll.ineligibility_reason = f"Objection upheld: {notes or claim.description}"
                claim.voter_roll.save(update_fields=['is_eligible', 'ineligibility_reason'])
            elif claim.claim_type == 'correction' and claim.voter_roll:
                if claim.target_voter_name:
                    parts = claim.target_voter_name.strip().split()
                    claim.voter_roll.first_name = parts[0] if parts else ''
                    claim.voter_roll.middle_name = " ".join(parts[1:-1]) if len(parts) > 2 else ''
                    claim.voter_roll.last_name = parts[-1] if len(parts) > 1 else ''
                    claim.voter_roll.save(update_fields=['first_name', 'middle_name', 'last_name'])

        # Notify claimant of resolution
        from apps.notifications.services import NotificationService
        try:
            NotificationService.notify_voter_claim_resolved(claim)
        except Exception as e:
            logger.warning(f"Failed to send voter claim resolution notification: {e}")

        log_action('voter_claim.resolved', claim.election.organization, request.user, {
            'election_id': str(claim.election.id),
            'claim_id': str(claim.id),
            'status': claim.status,
            'claim_type': claim.claim_type
        })
        return Response(VoterClaimSerializer(claim).data)


# ═══════════════════════════════════════════════════════════════════════════
# METHOD 1 TYPE 2 & 3: WEB-BASED SINGLE-USE BALLOT LINKS & STATS
# (doc: Election-Methods.pdf)
# ═══════════════════════════════════════════════════════════════════════════

import secrets
import hashlib
from datetime import timedelta
from django.conf import settings
from rest_framework.views import APIView
from rest_framework.permissions import AllowAny, IsAuthenticated
from apps.users.models import OTPRecord
from apps.notifications.services import NotificationService


class WebVotingOTPRequestView(APIView):
    """
    POST /v1/voting/request-web-otp/
    Public endpoint for Method 1 Type 2 / Type 3 voters requesting email OTP.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        election_id = request.data.get('election_id')
        identifier = (request.data.get('identifier') or request.data.get('email') or '').strip().lower()

        if not election_id or not identifier:
            return Response({'error': 'election_id and email or voter_id are required.'}, status=400)

        try:
            election = Election.objects.get(id=election_id)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        if election.state != 'voting_open':
            return Response({'error': 'Voting is not currently active for this election.'}, status=400)

        # Check election method
        if election.election_method == 'venue':
            return Response({
                'error': f'This election is configured for physical venue voting at {election.venue_name or "the venue"}. Remote web voting is disabled.'
            }, status=400)

        if election.online_type == 'mobile_app':
            return Response({
                'error': 'This election is configured for Mobile App voting only. Please use the mobile app to cast your ballot.'
            }, status=400)

        # Find VoterRoll
        from django.db.models import Q
        roll = VoterRoll.objects.filter(
            Q(email__iexact=identifier) | Q(voter_id__iexact=identifier) | Q(phone__iexact=identifier),
            election=election,
        ).first()

        if not roll:
            return Response({
                'error': 'No voter registration found with this email / Voter ID in the certified voter roll.'
            }, status=404)

        if not roll.is_eligible:
            return Response({
                'error': roll.ineligibility_reason or 'You are marked as ineligible to vote in this election.'
            }, status=403)

        # Partial Election Branch Verification (Requirement 7)
        if getattr(election, 'is_partial_election', False) and election.target_branches:
            target_branches_clean = [str(b).strip().lower() for b in election.target_branches if str(b).strip()]
            voter_branch = (roll.branch or '').strip().lower()
            if target_branches_clean and voter_branch not in target_branches_clean:
                branches_str = ", ".join(election.target_branches)
                return Response({
                    'error': f'This is a partial election for [{branches_str}] branches only. Your registered branch is "{roll.branch or "Unassigned"}".'
                }, status=403)

        if roll.has_voted:
            return Response({
                'error': 'You have already cast your ballot in this election. Each voter may only vote once.'
            }, status=400)

        if not roll.email:
            return Response({
                'error': 'No registered email address found on your voter profile. Please contact the election officer.'
            }, status=400)

        # Generate 6-digit OTP
        otp = f"{secrets.randbelow(1000000):06d}"
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()

        OTPRecord.objects.filter(identifier=roll.email.lower(), purpose='web_vote', is_used=False).delete()
        OTPRecord.objects.create(
            identifier=roll.email.lower(),
            purpose='web_vote',
            otp_hash=otp_hash,
            expires_at=timezone.now() + timedelta(minutes=10),
            ip_address=get_client_ip(request),
        )

        try:
            NotificationService.send_web_voting_otp_email(
                to_email=roll.email,
                voter_name=roll.full_name,
                otp_code=otp,
                election=election,
            )
        except Exception as e:
            logger.warning(f"Failed to dispatch web voting OTP email: {e}")

        # Mask email for privacy
        parts = roll.email.split('@')
        masked_user = parts[0][:2] + '***' if len(parts[0]) > 2 else parts[0] + '***'
        masked_email = f"{masked_user}@{parts[1]}" if len(parts) > 1 else roll.email

        return Response({
            'otp_sent': True,
            'masked_email': masked_email,
            'voter_id': roll.voter_id,
            'message': f'A 6-digit verification code has been dispatched to {masked_email}.',
        })


class WebVotingOTPVerifyView(APIView):
    """
    POST /v1/voting/verify-web-otp/
    Public endpoint: Verifies email OTP, marks voter as web-verified,
    generates a single-use direct ballot link and sends it via email.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        election_id = request.data.get('election_id')
        identifier = (request.data.get('identifier') or request.data.get('email') or '').strip().lower()
        otp = (request.data.get('otp') or '').strip()

        if not election_id or not identifier or not otp:
            return Response({'error': 'election_id, email/identifier, and otp are required.'}, status=400)

        try:
            election = Election.objects.get(id=election_id)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        from django.db.models import Q
        roll = VoterRoll.objects.filter(
            Q(email__iexact=identifier) | Q(voter_id__iexact=identifier) | Q(phone__iexact=identifier),
            election=election,
        ).first()

        if not roll or not roll.email:
            return Response({'error': 'Voter record not found.'}, status=404)

        if roll.has_voted:
            return Response({'error': 'You have already voted in this election.'}, status=400)

        # Validate OTP
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        otp_record = OTPRecord.objects.filter(
            identifier=roll.email.lower(),
            purpose='web_vote',
            otp_hash=otp_hash,
            is_used=False,
            expires_at__gt=timezone.now(),
        ).first()

        if not otp_record:
            return Response({'error': 'Invalid or expired verification code. Please request a new code.'}, status=400)

        otp_record.is_used = True
        otp_record.save(update_fields=['is_used'])

        # Generate Cryptographic Single-Use Ballot Token
        token = secrets.token_urlsafe(36)
        roll.verification_channel = 'web_email'
        roll.verified_at = timezone.now()
        roll.direct_ballot_token = token
        roll.direct_ballot_token_expires_at = timezone.now() + timedelta(hours=24)
        roll.direct_ballot_token_used = False
        roll.save(update_fields=[
            'verification_channel', 'verified_at',
            'direct_ballot_token', 'direct_ballot_token_expires_at', 'direct_ballot_token_used'
        ])

        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000').rstrip('/')
        direct_link = f"{frontend_url}/#/vote/direct/{token}"

        try:
            NotificationService.send_direct_ballot_link_email(
                to_email=roll.email,
                voter_name=roll.full_name,
                direct_link_url=direct_link,
                election=election,
            )
        except Exception as e:
            logger.warning(f"Failed to dispatch direct ballot link email: {e}")

        return Response({
            'verified': True,
            'direct_token': token,
            'direct_link_url': direct_link,
            'message': 'Identity verified! Your official single-use ballot link has been sent to your email.',
        })


class DirectBallotView(APIView):
    """
    GET /v1/voting/direct-ballot/<token>/
    Public endpoint: Validates single-use token and returns ballot paper without login.
    """
    permission_classes = [AllowAny]

    def get(self, request, token):
        roll = VoterRoll.objects.select_related('election', 'election__organization').filter(
            direct_ballot_token=token
        ).first()

        if not roll:
            return Response({'error': 'Invalid or unrecognized ballot link.'}, status=404)

        if roll.direct_ballot_token_used or roll.has_voted:
            return Response({
                'error': 'This ballot link has already been used. Each voter may only vote once.'
            }, status=410)

        if roll.direct_ballot_token_expires_at and timezone.now() > roll.direct_ballot_token_expires_at:
            return Response({
                'error': 'This ballot link has expired. Please verify your email again to receive a fresh link.'
            }, status=410)

        election = roll.election
        if election.state != 'voting_open':
            return Response({'error': f'Voting is not currently active for this election (Status: {election.get_state_display()}).'}, status=400)

        # Partial Election Branch Verification (Requirement 7)
        if getattr(election, 'is_partial_election', False) and election.target_branches:
            target_branches_clean = [str(b).strip().lower() for b in election.target_branches if str(b).strip()]
            voter_branch = (roll.branch or '').strip().lower()
            if target_branches_clean and voter_branch not in target_branches_clean:
                branches_str = ", ".join(election.target_branches)
                return Response({
                    'error': f'This is a partial election for [{branches_str}] branches only. Your registered branch is "{roll.branch or "Unassigned"}".'
                }, status=403)

        ballot_data = BallotService.generate_ballot(election)

        return Response({
            'election_id': str(election.id),
            'election_title': election.title,
            'election_prefix': election.prefix,
            'primary_color': election.primary_color,
            'secondary_color': election.secondary_color,
            'logo_url': election.logo_url,
            'is_secret_ballot': election.is_secret_ballot,
            'allow_boycott': election.allow_boycott,
            'election_type': getattr(election, 'election_type', 'fptp'),
            'enable_party': getattr(election, 'enable_party', True),
            'enable_panel': getattr(election, 'enable_panel', True),
            'enable_symbol': getattr(election, 'enable_symbol', True),
            'enable_candidate_photo': getattr(election, 'enable_candidate_photo', True),
            'is_partial_election': getattr(election, 'is_partial_election', False),
            'total_pr_seats': getattr(election, 'total_pr_seats', 10),
            'pr_threshold_percent': float(getattr(election, 'pr_threshold_percent', 0.00)),
            'pr_allocation_method': getattr(election, 'pr_allocation_method', 'modified_sainte_lague'),
            'voter_name': roll.full_name,
            'voter_id': roll.voter_id,
            'branch': roll.branch or '',
            'ballot': ballot_data,
        })


class DirectVoteCastView(APIView):
    """
    POST /v1/voting/direct-cast/<token>/
    Public endpoint: Casts the vote using single-use token and burns the token.
    """
    permission_classes = [AllowAny]

    def post(self, request, token):
        roll = VoterRoll.objects.select_related('election').filter(
            direct_ballot_token=token
        ).first()

        if not roll:
            return Response({'error': 'Invalid ballot link token.'}, status=404)

        if roll.direct_ballot_token_used or roll.has_voted:
            return Response({'error': 'This ballot token has already been burned/used.'}, status=410)

        if roll.direct_ballot_token_expires_at and timezone.now() > roll.direct_ballot_token_expires_at:
            return Response({'error': 'This ballot link has expired.'}, status=410)

        election = roll.election
        if election.state != 'voting_open':
            return Response({'error': 'Voting is not active.'}, status=400)

        # Validate votes payload
        payload_data = dict(request.data)
        if 'ballot_data' not in payload_data and 'votes' in payload_data:
            votes = payload_data['votes']
            if isinstance(votes, dict):
                payload_data['ballot_data'] = votes
            elif isinstance(votes, list):
                b_map = {}
                for v in votes:
                    pid = str(v.get('position_id', ''))
                    cid = v.get('candidate_id')
                    if pid:
                        if isinstance(cid, list):
                            b_map[pid] = [str(x) for x in cid]
                        elif cid:
                            b_map[pid] = [str(cid)]
                        elif v.get('is_boycott') or v.get('boycott'):
                            b_map[pid] = ['__BOYCOTT__']
                        elif v.get('is_nota') or v.get('none_of_the_above'):
                            b_map[pid] = ['NOTA']
                payload_data['ballot_data'] = b_map

        serializer = CastVoteSerializer(data=payload_data, context={'election': election})
        if not serializer.is_valid():
            return Response(serializer.errors, status=400)

        # Start one-time session and cast vote atomically
        try:
            session_token = BallotService.start_session(roll)
            ip_addr = get_client_ip(request)
            mac_addr = (
                request.data.get('device_identifier')
                or request.data.get('mac_address')
                or request.META.get('HTTP_X_DEVICE_IDENTIFIER', '')
            )
            receipt_hash = BallotService.cast_vote(
                session_token=session_token,
                ballot_data=serializer.validated_data['ballot_data'],
                ip_address=ip_addr,
                mac_address=mac_addr,
            )

            # Burn single-use direct ballot token
            roll.direct_ballot_token_used = True
            roll.save(update_fields=['direct_ballot_token_used'])

            return Response({
                'receipt_hash': receipt_hash,
                'message': 'Your ballot has been cast and cryptographically recorded.',
                'voted_at': timezone.now().isoformat(),
            })
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class ElectionVerificationStatsView(APIView):
    """
    GET /v1/elections/<id>/verification-stats/
    Admin / Officer endpoint returning real-time verification breakdown
    (Mobile App vs Web Email vs Venue Kiosk vs Unverified).
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, election_pk=None):
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        qs = VoterRoll.objects.filter(election=election)
        total_voters = qs.count()
        total_eligible = qs.filter(is_eligible=True).count()
        voted_count = qs.filter(has_voted=True).count()

        mobile_app = qs.filter(verification_channel='mobile_app').count()
        web_email = qs.filter(verification_channel='web_email').count()
        venue_kiosk = qs.filter(verification_channel='venue_kiosk').count()
        unverified = qs.filter(verification_channel='unverified').count()

        total_verified = mobile_app + web_email + venue_kiosk
        verification_rate = round((total_verified / total_voters * 100), 1) if total_voters > 0 else 0.0
        turnout_rate = round((voted_count / total_eligible * 100), 1) if total_eligible > 0 else 0.0

        return Response({
            'election_id': str(election.id),
            'election_title': election.title,
            'election_method': election.election_method,
            'online_type': election.online_type,
            'total_voters': total_voters,
            'total_eligible': total_eligible,
            'total_verified': total_verified,
            'verification_rate': verification_rate,
            'voted_count': voted_count,
            'turnout_rate': turnout_rate,
            'breakdown': {
                'mobile_app': {
                    'count': mobile_app,
                    'percentage': round((mobile_app / total_voters * 100), 1) if total_voters > 0 else 0.0,
                    'label': 'Verified via Mobile App',
                },
                'web_email': {
                    'count': web_email,
                    'percentage': round((web_email / total_voters * 100), 1) if total_voters > 0 else 0.0,
                    'label': 'Verified via Web / Email',
                },
                'venue_kiosk': {
                    'count': venue_kiosk,
                    'percentage': round((venue_kiosk / total_voters * 100), 1) if total_voters > 0 else 0.0,
                    'label': 'Verified at Venue Kiosk',
                },
                'unverified': {
                    'count': unverified,
                    'percentage': round((unverified / total_voters * 100), 1) if total_voters > 0 else 0.0,
                    'label': 'Pending Verification',
                },
            }
        })


# ═══════════════════════════════════════════════════════════════════════════
# METHOD 2: VENUE / DEVICE-BASED IN-PERSON VOTING KIOSKS (BOOTHS)
# (doc: Election-Methods.pdf)
# ═══════════════════════════════════════════════════════════════════════════

class KioskUnlockView(APIView):
    """
    POST /v1/voting/kiosk/unlock/
    Voter check-in at a physical polling station kiosk via Voter ID / QR scan.
    If require_venue_otp is True, generates & sends OTP code.
    If require_venue_otp is False, immediately unlocks ballot.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        election_id = request.data.get('election_id')
        voter_pin = (request.data.get('voter_pin') or request.data.get('pin') or '').strip()
        raw_identifier = (
            request.data.get('voter_id')
            or request.data.get('identifier')
            or request.data.get('email')
            or request.data.get('phone')
            or ''
        ).strip()

        if not election_id or (not raw_identifier and not voter_pin):
            return Response({'error': 'election_id and voter identifier or PIN are required.'}, status=400)

        # Automatically parse standard EMS QR Code payloads: EMS-VOTER:<voter_id>:<election_id>:<email/phone>
        if raw_identifier.startswith('EMS-VOTER:'):
            parts = raw_identifier.split(':')
            if len(parts) >= 2:
                raw_identifier = parts[1].strip()

        try:
            election = Election.objects.get(id=election_id)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        if election.state != 'voting_open':
            return Response({'error': f'Voting is not active for this election (Status: {election.get_state_display()}).'}, status=400)

        from django.db.models import Q

        roll = None
        if raw_identifier:
            roll = VoterRoll.objects.filter(
                Q(voter_id__iexact=raw_identifier)
                | Q(email__iexact=raw_identifier)
                | Q(phone__iexact=raw_identifier)
                | Q(council_number__iexact=raw_identifier)
                | Q(citizenship_number__iexact=raw_identifier)
                | Q(voter_pin__iexact=raw_identifier),
                election=election,
            ).first()
        elif voter_pin:
            roll = VoterRoll.objects.filter(election=election, voter_pin=voter_pin).first()

        if not roll:
            return Response({
                'error': f'No voter record found for "{raw_identifier or voter_pin}" in the electoral roll.'
            }, status=404)

        # Validate Secret Voting PIN if provided separately from identifier
        if voter_pin and raw_identifier and raw_identifier != voter_pin and roll.voter_pin and roll.voter_pin.strip():
            if roll.voter_pin.strip().lower() != voter_pin.strip().lower():
                return Response({
                    'error': 'Invalid Secret Voting PIN for this voter. Please check your token slip and try again.'
                }, status=400)

        if not roll.is_eligible:
            return Response({
                'error': roll.ineligibility_reason or 'You are marked as ineligible to vote in this election.'
            }, status=403)

        # Partial Election Branch Verification (Requirement 7)
        if getattr(election, 'is_partial_election', False) and election.target_branches:
            target_branches_clean = [str(b).strip().lower() for b in election.target_branches if str(b).strip()]
            voter_branch = (roll.branch or '').strip().lower()
            if target_branches_clean and voter_branch not in target_branches_clean:
                branches_str = ", ".join(election.target_branches)
                return Response({
                    'error': f'This is a partial election for [{branches_str}] branches only. Your registered branch is "{roll.branch or "Unassigned"}".'
                }, status=403)

        if roll.has_voted:
            return Response({
                'error': f'Voter {roll.full_name} ({roll.voter_id}) has already cast their ballot in this election.'
            }, status=400)

        # 2nd Layer Verification Check (Method 2 Option)
        if election.require_venue_otp:
            otp = f"{secrets.randbelow(1000000):06d}"
            otp_hash = hashlib.sha256(otp.encode()).hexdigest()
            target_id = (roll.email or roll.phone or roll.voter_id).lower()

            OTPRecord.objects.filter(identifier=target_id, purpose='venue_vote', is_used=False).delete()
            OTPRecord.objects.create(
                identifier=target_id,
                purpose='venue_vote',
                otp_hash=otp_hash,
                expires_at=timezone.now() + timedelta(minutes=10),
                ip_address=get_client_ip(request),
            )

            try:
                NotificationService.send_venue_kiosk_otp(roll, otp, election)
            except Exception as e:
                logger.warning(f"Failed to dispatch kiosk OTP: {e}")

            # Masked details for display
            masked_phone = (roll.phone[:3] + '****' + roll.phone[-2:]) if len(roll.phone) >= 6 else roll.phone
            masked_email = ''
            if roll.email and '@' in roll.email:
                parts = roll.email.split('@')
                masked_email = (parts[0][:2] + '***@' + parts[1]) if len(parts[0]) > 2 else roll.email

            return Response({
                'require_otp': True,
                'otp_sent': True,
                'voter_name': roll.full_name,
                'voter_id': roll.voter_id,
                'venue_otp_channel': election.venue_otp_channel,
                'masked_phone': masked_phone,
                'masked_email': masked_email,
                'message': f'2nd-layer verification required. A 6-digit code was sent to your registered {election.venue_otp_channel.upper()}.',
            })

        # Immediate Ballot Unlock (No 2nd layer OTP)
        try:
            session_token = BallotService.start_session(roll)
            roll.verification_channel = 'venue_kiosk'
            roll.verified_at = timezone.now()
            roll.save(update_fields=['verification_channel', 'verified_at'])

            ballot_data = BallotService.generate_ballot(election)
            return Response({
                'require_otp': False,
                'session_token': session_token,
                'voter_name': roll.full_name,
                'voter_id': roll.voter_id,
                'branch': roll.branch or '',
                'election_title': election.title,
                'venue_name': election.venue_name,
                'allow_boycott': election.allow_boycott,
                'election_type': getattr(election, 'election_type', 'fptp'),
                'enable_party': getattr(election, 'enable_party', True),
                'enable_panel': getattr(election, 'enable_panel', True),
                'enable_symbol': getattr(election, 'enable_symbol', True),
                'enable_candidate_photo': getattr(election, 'enable_candidate_photo', True),
                'is_partial_election': getattr(election, 'is_partial_election', False),
                'total_pr_seats': getattr(election, 'total_pr_seats', 10),
                'pr_threshold_percent': float(getattr(election, 'pr_threshold_percent', 0.00)),
                'pr_allocation_method': getattr(election, 'pr_allocation_method', 'modified_sainte_lague'),
                'ballot': ballot_data,
                'message': 'Identity verified. Official voting booth unlocked.',
            })
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class KioskVerifyOTPView(APIView):
    """
    POST /v1/voting/kiosk/verify-otp/
    Verifies 2nd layer OTP at kiosk and unlocks the ballot paper.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        election_id = request.data.get('election_id')
        identifier = (
            request.data.get('voter_id')
            or request.data.get('identifier')
            or request.data.get('email')
            or request.data.get('phone')
            or ''
        ).strip()
        otp = (request.data.get('otp') or '').strip()

        if not election_id or not identifier or not otp:
            return Response({'error': 'election_id, voter identifier, and 6-digit otp are required.'}, status=400)

        try:
            election = Election.objects.get(id=election_id)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        from django.db.models import Q
        roll = VoterRoll.objects.filter(
            Q(voter_pin__iexact=identifier)
            | Q(voter_id__iexact=identifier)
            | Q(email__iexact=identifier)
            | Q(phone__iexact=identifier),
            election=election,
        ).first()

        if not roll:
            return Response({'error': 'Voter record not found.'}, status=404)

        if roll.has_voted:
            return Response({'error': 'Voter has already cast their ballot.'}, status=400)

        # Validate OTP
        otp_hash = hashlib.sha256(otp.encode()).hexdigest()
        target_id = (roll.email or roll.phone or roll.voter_id).lower()

        otp_record = OTPRecord.objects.filter(
            identifier=target_id,
            purpose='venue_vote',
            otp_hash=otp_hash,
            is_used=False,
            expires_at__gt=timezone.now(),
        ).first()

        if not otp_record:
            return Response({'error': 'Invalid or expired verification code. Please request a new code.'}, status=400)

        otp_record.is_used = True
        otp_record.save(update_fields=['is_used'])

        try:
            session_token = BallotService.start_session(roll)
            roll.verification_channel = 'venue_kiosk'
            roll.verified_at = timezone.now()
            roll.save(update_fields=['verification_channel', 'verified_at'])

            ballot_data = BallotService.generate_ballot(election)
            return Response({
                'verified': True,
                'session_token': session_token,
                'voter_name': roll.full_name,
                'voter_id': roll.voter_id,
                'election_title': election.title,
                'venue_name': election.venue_name,
                'allow_boycott': election.allow_boycott,
                'ballot': ballot_data,
                'message': '2nd-layer verification successful. Official voting booth unlocked.',
            })
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class KioskCastVoteView(APIView):
    """
    POST /v1/voting/kiosk/cast/
    Casts secret ballot on venue kiosk device and returns receipt hash.
    """
    permission_classes = [AllowAny]

    def post(self, request):
        session_token = request.data.get('session_token')
        election_id = request.data.get('election_id')

        if not session_token:
            return Response({'error': 'session_token is required.'}, status=400)

        try:
            election = Election.objects.get(id=election_id) if election_id else None
        except Election.DoesNotExist:
            election = None

        payload_data = dict(request.data)
        if 'ballot_data' not in payload_data and 'votes' in payload_data:
            votes = payload_data['votes']
            if isinstance(votes, dict):
                payload_data['ballot_data'] = votes
            elif isinstance(votes, list):
                b_map = {}
                for v in votes:
                    pid = str(v.get('position_id', ''))
                    cid = v.get('candidate_id')
                    if pid:
                        if isinstance(cid, list):
                            b_map[pid] = [str(x) for x in cid]
                        elif cid:
                            b_map[pid] = [str(cid)]
                        elif v.get('is_boycott') or v.get('boycott'):
                            b_map[pid] = ['__BOYCOTT__']
                        elif v.get('is_nota') or v.get('none_of_the_above'):
                            b_map[pid] = ['NOTA']
                payload_data['ballot_data'] = b_map

        ballot_data = payload_data.get('ballot_data', {})

        try:
            ip_addr = get_client_ip(request)
            mac_addr = (
                request.data.get('device_identifier')
                or request.data.get('station_id')
                or request.META.get('HTTP_X_DEVICE_IDENTIFIER', 'kiosk_station')
            )
            receipt_hash = BallotService.cast_vote(
                session_token=session_token,
                ballot_data=ballot_data,
                ip_address=ip_addr,
                mac_address=mac_addr,
            )

            return Response({
                'receipt_hash': receipt_hash,
                'voted_at': timezone.now().isoformat(),
                'message': 'Your secret ballot has been cast and cryptographically recorded on this kiosk station.',
                'auto_reset_seconds': 5,
            })
        except ValueError as e:
            return Response({'error': str(e)}, status=400)


class PollingStationInitializeView(APIView):
    """
    POST /v1/elections/<uuid:election_pk>/polling-stations/initialize/
    Initializes physical polling station and generates guaranteed unique, collision-free PINs for all voters.
    """
    permission_classes = [IsAuthenticated]

    def post(self, request, election_pk):
        try:
            election = Election.objects.get(id=election_pk)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found.'}, status=404)

        if request.user.organization_id != election.organization_id and not request.user.is_superuser:
            return Response({'error': 'Permission denied.'}, status=403)

        regenerate_all = bool(request.data.get('regenerate_all', False))
        station_name = str(request.data.get('station_name', '')).strip() or election.venue_name or 'Main Polling Booth'
        station_code = str(request.data.get('station_code', '')).strip() or 'STATION-01'

        voters = list(VoterRoll.objects.filter(election=election))
        if not voters:
            return Response({
                'error': 'No voters found in this election roll. Please import or register voters first before initializing the polling station.'
            }, status=400)

        existing_pins = set() if regenerate_all else set(
            VoterRoll.objects.filter(election=election)
            .exclude(voter_pin='')
            .values_list('voter_pin', flat=True)
        )

        updated_voters = []
        pins_generated = 0

        for voter in voters:
            if regenerate_all or not voter.voter_pin:
                pin = VoterRoll.generate_unique_pin_for_election(election, existing_pins=existing_pins)
                voter.voter_pin = pin
                updated_voters.append(voter)
                pins_generated += 1

        if updated_voters:
            VoterRoll.objects.bulk_update(updated_voters, ['voter_pin'], batch_size=500)

        return Response({
            'status': 'success',
            'message': f'Polling station "{station_name}" ({station_code}) initialized successfully. {pins_generated} unique voter PIN(s) generated.',
            'station_name': station_name,
            'station_code': station_code,
            'total_voters': len(voters),
            'pins_generated': pins_generated,
            'initialized_at': timezone.now().isoformat(),
        }, status=200)


class VoterPinSlipsPrintView(APIView):
    """
    GET /v1/elections/<uuid:election_pk>/voter-pins/print-slips/
    Returns a printable A4 letterhead of official voter PIN slips (8 slips per page) for station distribution.
    """
    permission_classes = [AllowAny]

    def get(self, request, election_pk):
        from django.http import HttpResponse
        try:
            election = Election.objects.get(id=election_pk)
        except Election.DoesNotExist:
            return HttpResponse('Election not found', status=404)

        org = election.organization
        org_name = org.name if org else 'Election Authority'
        voters = VoterRoll.objects.filter(election=election, is_eligible=True).order_by('voter_id', 'first_name')

        slips_html = ""
        for v in voters:
            pin_display = v.voter_pin or 'NOT-SET'
            slips_html += f"""
            <div class="pin-slip">
              <div class="slip-header">
                <div class="org-name">{org_name}</div>
                <div class="election-title">{election.title}</div>
              </div>
              <div class="slip-badge">मतदाता मतदान टोकन • OFFICIAL VOTER PIN SLIP</div>
              <div class="slip-body">
                <div class="slip-row"><span class="lbl">मतदाता (Name):</span> <span class="val">{v.full_name}</span></div>
                <div class="slip-row"><span class="lbl">मतदाता नं. (Voter ID):</span> <span class="val">{v.voter_id or '—'}</span></div>
                {f'<div class="slip-row"><span class="lbl">काउन्सिल/सदस्य नं.:</span> <span class="val">{v.council_number}</span></div>' if v.council_number else ''}
                {f'<div class="slip-row"><span class="lbl">नागरिकता नं.:</span> <span class="val">{v.citizenship_number}</span></div>' if v.citizenship_number else ''}
              </div>
              <div class="pin-box">
                <div class="pin-label">तपाईंको गोप्य मतदान पिन (SECRET VOTING PIN)</div>
                <div class="pin-value">{pin_display}</div>
              </div>
              <div class="slip-footer">
                मतदान बुथको स्क्रिनमा यो पिन प्रविष्ट गरी मतदान गर्नुहोस्। (One-time secure access)
              </div>
            </div>
            """

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>Voter PIN Slips - {election.title}</title>
  <style>
    @page {{
      size: A4 portrait;
      margin: 8mm;
    }}
    @media print {{
      body {{ margin: 0; padding: 0; background: white; }}
      .no-print {{ display: none !important; }}
    }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', Arial, sans-serif;
      background: #F1F5F9;
      margin: 0;
      padding: 16px;
      color: #0F172A;
    }}
    .action-bar {{
      max-width: 860px;
      margin: 0 auto 16px auto;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }}
    .btn {{
      background: #4F46E5;
      color: white;
      border: none;
      padding: 8px 18px;
      border-radius: 6px;
      font-weight: bold;
      cursor: pointer;
      font-size: 13px;
    }}
    .btn:hover {{ background: #4338CA; }}
    .grid-container {{
      max-width: 860px;
      margin: 0 auto;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
    }}
    .pin-slip {{
      background: white;
      border: 1.5px dashed #64748B;
      border-radius: 8px;
      padding: 10px 12px;
      box-sizing: border-box;
      page-break-inside: avoid;
    }}
    .slip-header {{
      text-align: center;
      border-bottom: 1px solid #E2E8F0;
      padding-bottom: 3px;
      margin-bottom: 4px;
    }}
    .org-name {{
      font-size: 10.5px;
      font-weight: 800;
      color: #0F172A;
    }}
    .election-title {{
      font-size: 9.5px;
      font-weight: 600;
      color: #4F46E5;
    }}
    .slip-badge {{
      background: #EFF6FF;
      color: #1E40AF;
      font-size: 8px;
      font-weight: bold;
      text-align: center;
      padding: 2px 4px;
      border-radius: 4px;
      margin-bottom: 5px;
    }}
    .slip-body {{
      font-size: 10px;
      line-height: 1.35;
      margin-bottom: 6px;
    }}
    .slip-row {{
      display: flex;
      justify-content: space-between;
      margin-bottom: 2px;
    }}
    .lbl {{
      color: #64748B;
      font-size: 9px;
    }}
    .val {{
      font-weight: bold;
      color: #0F172A;
    }}
    .pin-box {{
      background: #FFFBEB;
      border: 1.2px solid #F59E0B;
      border-radius: 6px;
      padding: 4px 6px;
      text-align: center;
      margin-bottom: 5px;
    }}
    .pin-label {{
      font-size: 7.5px;
      font-weight: bold;
      color: #B45309;
      letter-spacing: 0.3px;
    }}
    .pin-value {{
      font-size: 18px;
      font-weight: 900;
      letter-spacing: 3px;
      color: #B91C1C;
      font-family: monospace;
      margin-top: 1px;
    }}
    .slip-footer {{
      font-size: 7.5px;
      color: #64748B;
      text-align: center;
      font-style: italic;
    }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <div style="font-weight: bold; font-size: 14px;">Total Eligible Voters: {voters.count()}</div>
    <button class="btn" onclick="window.print()">🖨️ Print All Voter PIN Slips</button>
  </div>
  <div class="grid-container">
    {slips_html}
  </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html')



