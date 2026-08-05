from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.members.models import Member, MemberImportJob
from apps.members.serializers import MemberSerializer, MemberImportJobSerializer
from apps.core.permissions import IsOrgAdmin

class MemberViewSet(viewsets.ModelViewSet):
    """
    Manage organization members (voters/candidates).
    """
    serializer_class = MemberSerializer
    permission_classes = [IsOrgAdmin] # Only Org Admins can manage members
    
    def get_queryset(self):
        return Member.objects.filter(organization=self.request.user.organization)

    def perform_create(self, serializer):
        serializer.save(organization=self.request.user.organization)

    @action(detail=False, methods=['post'])
    def import_csv(self, request):
        """
        Placeholder for CSV import via Celery.
        Expects a file upload.
        """
        if 'file' not in request.FILES:
            return Response({'error': 'No file uploaded'}, status=status.HTTP_400_BAD_REQUEST)
            
        file = request.FILES['file']
        # In a real app, upload file to S3/storage, get URL
        file_url = f"dummy_url_for_{file.name}"
        
        job = MemberImportJob.objects.create(
            organization=request.user.organization,
            initiated_by=request.user,
            file_url=file_url,
            status='pending'
        )
        
        # trigger celery task here: process_member_import.delay(job.id)
        
        serializer = MemberImportJobSerializer(job)
        return Response(serializer.data, status=status.HTTP_202_ACCEPTED)
