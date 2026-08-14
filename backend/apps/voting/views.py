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
