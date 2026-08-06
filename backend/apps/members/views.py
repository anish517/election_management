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
        return Member.objects.filter(organization=self.request.user.organization)

    def perform_create(self, serializer):
        serializer.save(organization=self.request.user.organization)

    @action(detail=False, methods=['post'])
    def import_csv(self, request):
        """
        Process CSV upload synchronously for MVP.
        Expects a file upload with columns: full_name, email, member_code, phone
        """
        import csv
        import io

        if 'file' not in request.FILES:
            return Response({'error': 'No file uploaded'}, status=status.HTTP_400_BAD_REQUEST)
            
        file = request.FILES['file']
        try:
            decoded_file = file.read().decode('utf-8')
            io_string = io.StringIO(decoded_file)
            reader = csv.DictReader(io_string)
            
            created_count = 0
            for row in reader:
                Member.objects.get_or_create(
                    organization=request.user.organization,
                    email=row.get('email', '').strip(),
                    defaults={
                        'full_name': row.get('full_name', '').strip(),
                        'member_code': row.get('member_code', '').strip(),
                        'phone': row.get('phone', '').strip(),
                        'membership_status': 'active'
                    }
                )
                created_count += 1
                
            return Response({'message': f'Successfully processed {created_count} members.'}, status=status.HTTP_200_OK)
        except Exception as e:
            return Response({'error': f'Failed to process CSV: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)
