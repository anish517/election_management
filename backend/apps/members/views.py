from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.members.models import Member, MemberImportJob
from apps.members.serializers import MemberSerializer, MemberImportJobSerializer
from apps.core.permissions import IsOrgAdmin, IsOrgAdminOrReadOnly

class MemberViewSet(viewsets.ModelViewSet):
    """
    Manage organization members (voters/candidates).
    """
    serializer_class = MemberSerializer
    permission_classes = [IsOrgAdminOrReadOnly] # Org Admins manage, others can read
    
    def get_queryset(self):
        user = self.request.user
        if user.is_superuser or getattr(user, 'role', '') == 'super_admin':
            org_id = self.request.query_params.get('organization') or self.request.query_params.get('organization_id')
            election_id = self.request.query_params.get('election') or self.request.query_params.get('election_id')
            if org_id:
                return Member.objects.filter(organization_id=org_id)
            if election_id:
                from apps.elections.models import Election
                el = Election.objects.filter(id=election_id).first()
                if el and el.organization_id:
                    return Member.objects.filter(organization_id=el.organization_id)
            return Member.objects.all()
        return Member.objects.filter(organization=user.organization)

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser or getattr(user, 'role', '') == 'super_admin':
            org_id = self.request.data.get('organization') or self.request.query_params.get('organization')
            if org_id:
                from apps.organizations.models import Organization
                org = Organization.objects.filter(id=org_id).first()
                if org:
                    serializer.save(organization=org)
                    return
            from apps.organizations.models import Organization
            first_org = Organization.objects.first()
            serializer.save(organization=first_org)
            return
        serializer.save(organization=self.request.user.organization)

    @action(detail=False, methods=['post'])
    def preview_csv(self, request):
        """
        Step 1 of the Import Wizard: Parse CSV + apply column mapping,
        return a preview of valid/error rows WITHOUT writing to the database.
        
        Payload: multipart/form-data
          - file: the CSV file
          - mapping: JSON string like {"Name": "full_name", "Email": "email", ...}
        """
        import csv
        import io
        import json

        if 'file' not in request.FILES:
            return Response({'error': 'No file uploaded'}, status=status.HTTP_400_BAD_REQUEST)

        mapping_raw = request.data.get('mapping', '{}')
        try:
            mapping = json.loads(mapping_raw)  # { csv_col -> db_field }
        except (json.JSONDecodeError, TypeError):
            mapping = {}

        file = request.FILES['file']
        try:
            decoded_file = file.read().decode('utf-8-sig')  # utf-8-sig handles BOM from Excel
            io_string = io.StringIO(decoded_file)
            reader = csv.DictReader(io_string)
            columns = reader.fieldnames or []

            valid_rows = []
            error_rows = []

            target_org = request.user.organization
            if not target_org and (request.user.is_superuser or getattr(request.user, 'role', '') == 'super_admin'):
                org_id = request.data.get('organization')
                if org_id:
                    from apps.organizations.models import Organization
                    target_org = Organization.objects.filter(id=org_id).first()
                if not target_org:
                    from apps.organizations.models import Organization
                    target_org = Organization.objects.first()

            org_filter = {'organization': target_org} if target_org else {}
            existing_emails = set(
                Member.objects.filter(**org_filter)
                .values_list('email', flat=True)
            )
            existing_codes = set(
                Member.objects.filter(**org_filter)
                .exclude(member_code='')
                .values_list('member_code', flat=True)
            )

            for i, row in enumerate(reader, start=2):  # start=2 because row 1 is header
                # Apply column mapping
                mapped = {}
                for csv_col, db_field in mapping.items():
                    mapped[db_field] = row.get(csv_col, '').strip()

                # Also try direct field names in case they match exactly
                for field in ['full_name', 'email', 'member_code', 'phone', 'department', 'region', 'position_title', 'voting_weight']:
                    if field not in mapped and field in row:
                        mapped[field] = row.get(field, '').strip()

                email = mapped.get('email', '')
                full_name = mapped.get('full_name', '')
                member_code = mapped.get('member_code', '')

                # Validate
                error = None
                if not email:
                    error = 'Email is missing'
                elif '@' not in email:
                    error = f'"{email}" is not a valid email address'
                elif email in existing_emails:
                    error = f'Member with email "{email}" already exists'
                elif member_code and member_code in existing_codes:
                    error = f'Member Code "{member_code}" already exists'

                if error:
                    error_rows.append({
                        'row': i,
                        'data': dict(row),
                        'mapped': mapped,
                        'error': error,
                    })
                else:
                    existing_emails.add(email)  # track within-file duplicates
                    if member_code:
                        existing_codes.add(member_code)
                    valid_rows.append({
                        'row': i,
                        'full_name': full_name,
                        'email': email,
                        'member_code': mapped.get('member_code', ''),
                        'phone': mapped.get('phone', ''),
                        'department': mapped.get('department', ''),
                        'region': mapped.get('region', ''),
                        'position_title': mapped.get('position_title', ''),
                        'voting_weight': mapped.get('voting_weight', '1.0'),
                    })

            return Response({
                'columns': columns,
                'valid_count': len(valid_rows),
                'error_count': len(error_rows),
                'valid_rows': valid_rows,
                'error_rows': error_rows,
            })

        except Exception as e:
            return Response({'error': f'Failed to parse CSV: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=False, methods=['post'])
    def import_csv(self, request):
        """
        Step 2 of the Import Wizard: Commit valid rows to the database.
        
        Payload: multipart/form-data
          - file: the CSV file
          - mapping: JSON string like {"Name": "full_name", "Email": "email", ...}
        """
        import csv
        import io
        import json

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

            from django.contrib.auth import get_user_model
            User = get_user_model()

            target_org = request.user.organization
            if not target_org and (request.user.is_superuser or getattr(request.user, 'role', '') == 'super_admin'):
                org_id = request.data.get('organization')
                if org_id:
                    from apps.organizations.models import Organization
                    target_org = Organization.objects.filter(id=org_id).first()
                if not target_org:
                    from apps.organizations.models import Organization
                    target_org = Organization.objects.first()

            org_filter = {'organization': target_org} if target_org else {}
            existing_emails = set(
                Member.objects.filter(**org_filter)
                .values_list('email', flat=True)
            )
            existing_codes = set(
                Member.objects.filter(**org_filter)
                .exclude(member_code='')
                .values_list('member_code', flat=True)
            )

            imported_count = 0
            skipped_count = 0
            errors = []

            for i, row in enumerate(reader, start=2):
                # Apply column mapping
                mapped = {}
                for csv_col, db_field in mapping.items():
                    mapped[db_field] = row.get(csv_col, '').strip()

                # Direct field fallback
                for field in ['full_name', 'email', 'member_code', 'phone', 'department', 'region', 'position_title', 'voting_weight', 'photo_url', 'gender', 'membership_status', 'membership_expiry_date']:
                    if field not in mapped and field in row:
                        mapped[field] = row.get(field, '').strip()

                email = mapped.get('email', '')
                member_code = mapped.get('member_code', '')
                if not email or '@' not in email or email in existing_emails or (member_code and member_code in existing_codes):
                    skipped_count += 1
                    continue

                try:
                    voting_weight = float(mapped.get('voting_weight', '1.0') or '1.0')
                except (ValueError, TypeError):
                    voting_weight = 1.0

                member, created = Member.objects.get_or_create(
                    organization=target_org or request.user.organization,
                    email=email,
                    defaults={
                        'full_name': mapped.get('full_name', ''),
                        'member_code': mapped.get('member_code', ''),
                        'phone': mapped.get('phone', ''),
                        'department': mapped.get('department', ''),
                        'region': mapped.get('region', ''),
                        'position_title': mapped.get('position_title', ''),
                        'voting_weight': voting_weight,
                        'membership_status': (mapped.get('membership_status') or 'active').lower(),
                        'photo_url': mapped.get('photo_url', ''),
                        'gender': mapped.get('gender', ''),
                    }
                )

                if created:
                    # Handle date parsing for membership_expiry_date safely
                    expiry_raw = mapped.get('membership_expiry_date', '')
                    if expiry_raw:
                        try:
                            from dateutil import parser
                            member.membership_expiry_date = parser.parse(expiry_raw).date()
                            member.save(update_fields=['membership_expiry_date'])
                        except Exception:
                            pass
                    # Create login account so member can log in
                    user, user_created = User.objects.get_or_create(
                        email=email,
                        defaults={
                            'role': 'member',
                            'organization': request.user.organization,
                        }
                    )
                    if not user_created:
                        user.organization = request.user.organization
                        user.save()
                    member.user = user
                    member.save(update_fields=['user'])

                existing_emails.add(email)
                if member_code:
                    existing_codes.add(member_code)
                imported_count += 1

            return Response({
                'message': f'Import complete. {imported_count} members added, {skipped_count} rows skipped.',
                'imported': imported_count,
                'skipped': skipped_count,
                'errors': errors,
            })

        except Exception as e:
            return Response({'error': f'Failed to import CSV: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)


    @action(detail=False, methods=['get'])
    def export_csv(self, request):
        """
        Export all members to CSV.
        """
        import csv
        from django.http import HttpResponse

        members = self.get_queryset()
        
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="members_export.csv"'
        
        writer = csv.writer(response)
        writer.writerow(['Member Code', 'Full Name', 'Email', 'Phone', 'Department', 'Position Title', 'Status', 'Voting Weight'])
        
        for m in members:
            writer.writerow([
                m.member_code,
                m.full_name,
                m.email,
                m.phone,
                m.department,
                m.position_title,
                m.membership_status,
                m.voting_weight,
            ])
            
        return response
