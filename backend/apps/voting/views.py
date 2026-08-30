from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

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
            'voter_info': {
                'voter_id': voter_id,
                'full_name': voter_name,
                'email': request.user.email,
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

        if roll.has_voted:
            return Response({'error': 'You have already cast your ballot in this election. Each voter may only vote once.'}, status=403)

        if roll.election.state != 'voting_open':
            return Response({'error': 'Voting is not currently active.'}, status=400)

        try:
            token = BallotService.start_session(roll)
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
        writer.writerow(['Voter ID', 'Prefix', 'First Name', 'Middle Name', 'Last Name', 'Email', 'Phone', 'Council Number', 'Citizenship Number', 'Eligible'])
        for v in voters:
            writer.writerow([v.voter_id, v.prefix, v.first_name, v.middle_name, v.last_name, v.email, v.phone, v.council_number, v.citizenship_number, v.is_eligible])
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
