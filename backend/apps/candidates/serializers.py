from rest_framework import serializers
from apps.candidates.models import Candidate, CandidateDocument, CandidateEndorsement
from django.db import transaction

class CandidateDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = CandidateDocument
        fields = ['id', 'document_type', 'file_url', 'uploaded_at']
        read_only_fields = ['id', 'uploaded_at']

class CandidateEndorsementSerializer(serializers.ModelSerializer):
    class Meta:
        model = CandidateEndorsement
        fields = ['id', 'endorsement_type', 'name', 'citizenship_number', 'phone', 'membership_id', 'signature_url']
        read_only_fields = ['id']

class CandidateSerializer(serializers.ModelSerializer):
    documents = CandidateDocumentSerializer(many=True, read_only=True)
    endorsements = CandidateEndorsementSerializer(many=True, required=False)
    
    position_title = serializers.CharField(source='position.title', read_only=True)
    full_name = serializers.CharField(read_only=True)
    
    class Meta:
        model = Candidate
        fields = [
            'id', 'election', 'position', 'position_title', 
            'first_name', 'middle_name', 'last_name', 'full_name',
            'email', 'contact_number', 'gender', 'date_of_birth', 'address',
            'candidate_image', 'candidate_signature', 'personal_description', 'contribution_to_org',
            'manifesto', 'status', 'slate_name', 'documents', 'endorsements', 
            'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'election', 'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at', 'full_name']

    @transaction.atomic
    def create(self, validated_data):
        endorsements_data = validated_data.pop('endorsements', [])
        candidate = Candidate.objects.create(**validated_data)
        for end_data in endorsements_data:
            CandidateEndorsement.objects.create(candidate=candidate, **end_data)
        return candidate

    @transaction.atomic
    def update(self, instance, validated_data):
        endorsements_data = validated_data.pop('endorsements', None)
        
        # Standard model fields update
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        # Update endorsements if provided (replace all strategy)
        if endorsements_data is not None:
            instance.endorsements.all().delete()
            for end_data in endorsements_data:
                CandidateEndorsement.objects.create(candidate=instance, **end_data)

        return instance
