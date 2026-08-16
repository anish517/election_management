from rest_framework import viewsets, status
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
            user_email = request.user.email.strip().lower()
            roll = VoterRoll.objects.filter(election=election, email__iexact=user_email).first()
            if not roll:
                from apps.candidates.models import Candidate
                from apps.members.models import Member
                # Check if user is a registered candidate in this election
                cand = Candidate.objects.filter(position__election=election, email__iexact=user_email).first()
                if cand:
                    roll, _ = VoterRoll.objects.get_or_create(
                        election=election,
                        email=user_email,
                        defaults={
                            'first_name': cand.full_name,
                            'phone': cand.contact_number or '',
                            'is_eligible': True,
                            'voter_id': f"CAND-{cand.id.hex[:6].upper()}",
                        }
                    )
                else:
                    # Check if user is a member of this organization
                    member = Member.objects.filter(organization=election.organization, email__iexact=user_email).first()
                    if member:
                        roll, _ = VoterRoll.objects.get_or_create(
                            election=election,
                            email=user_email,
                            defaults={
                                'first_name': member.first_name,
                                'last_name': member.last_name,
                                'phone': member.phone,
                                'is_eligible': member.is_eligible_to_vote,
                                'voter_id': member.member_code or f"MEM-{member.id.hex[:6].upper()}",
                            }
                        )
            return roll
        except Exception:
            return None

    @action(detail=False, methods=['get'])
    def ballot(self, request, election_pk=None):
        """Returns the structured ballot with approved candidates."""
        try:
            election = Election.objects.get(id=election_pk, organization=request.user.organization)
        except Election.DoesNotExist:
            return Response({'error': 'Election not found'}, status=404)
            
        ballot_data = BallotService.generate_ballot(election)
        return Response({
            'ballot': ballot_data,
            'allow_boycott': election.allow_boycott,
            'is_secret_ballot': election.is_secret_ballot,
        })

    @action(detail=False, methods=['post'])
    def session(self, request, election_pk=None):
        """Generates a voting session token."""
        roll = self._get_voter_roll(request, election_pk)
        if not roll:
            return Response({'error': 'You are not eligible to vote in this election.'}, status=403)
            
        if roll.election.state != 'voting_open':
            return Response({'error': 'Voting is not active.'}, status=400)
            
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
    permission_classes = [IsAuthenticated] # Could be IsElectionOfficer or IsOrgAdmin for write

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
        from rest_framework.exceptions import ValidationError
        election_pk = self.kwargs.get('election_pk')
        election = Election.objects.get(id=election_pk, organization=self.request.user.organization)
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
                if not VoterRoll.objects.filter(election=claim.election, email__iexact=claim.claimant_email).exists():
                    VoterRoll.objects.create(
                        election=claim.election,
                        first_name=claim.claimant_name,
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
                    claim.voter_roll.first_name = claim.target_voter_name
                    claim.voter_roll.save(update_fields=['first_name'])

        log_action('voter_claim.resolved', claim.election.organization, request.user, {
            'election_id': str(claim.election.id),
            'claim_id': str(claim.id),
            'status': claim.status,
            'claim_type': claim.claim_type
        })
        return Response(VoterClaimSerializer(claim).data)
