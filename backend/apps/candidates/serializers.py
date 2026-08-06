from rest_framework import serializers
from apps.candidates.models import Candidate, CandidateDocument
from apps.members.models import Member

class CandidateDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = CandidateDocument
        fields = ['id', 'document_type', 'file_url', 'uploaded_at']
        read_only_fields = ['id', 'uploaded_at']

class CandidateSerializer(serializers.ModelSerializer):
    documents = CandidateDocumentSerializer(many=True, read_only=True)
    member = serializers.PrimaryKeyRelatedField(queryset=Member.objects.all(), required=False, allow_null=True)
    member_name = serializers.CharField(source='member.full_name', read_only=True)
    
    class Meta:
        model = Candidate
        fields = [
            'id', 'election', 'position', 'member', 'member_name', 'manifesto',
            'status', 'slate_name', 'documents', 'reviewed_by',
            'review_notes', 'reviewed_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'election', 'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at']
