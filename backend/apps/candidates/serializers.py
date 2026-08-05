from rest_framework import serializers
from apps.candidates.models import Candidate, CandidateDocument

class CandidateDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = CandidateDocument
        fields = ['id', 'document_type', 'file_url', 'uploaded_at']
        read_only_fields = ['id', 'uploaded_at']

class CandidateSerializer(serializers.ModelSerializer):
    documents = CandidateDocumentSerializer(many=True, read_only=True)
    
    class Meta:
        model = Candidate
        fields = [
            'id', 'election', 'position', 'member', 'manifesto',
            'status', 'slate_name', 'documents', 'reviewed_by',
            'review_notes', 'reviewed_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'status', 'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at']
