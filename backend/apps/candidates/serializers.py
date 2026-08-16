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
            'id', 'election', 'position', 'position_title', 'quota', 'quota_name',
            'first_name', 'middle_name', 'last_name', 'full_name',
            'email', 'contact_number', 'gender', 'date_of_birth', 'address',
            'candidate_image', 'personal_description', 'contribution_to_org',
            'manifesto', 'status', 'documents', 'endorsements', 
            'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'election', 'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at', 'full_name']

    @transaction.atomic
    def create(self, validated_data):
        endorsements_data = validated_data.pop('endorsements', [])
        quota = validated_data.get('quota')
        if quota and not validated_data.get('quota_name'):
            validated_data['quota_name'] = quota.name
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
        if 'quota' in validated_data and instance.quota and not validated_data.get('quota_name'):
            instance.quota_name = instance.quota.name
        instance.save()

        # Update endorsements if provided (replace all strategy)
        if endorsements_data is not None:
            instance.endorsements.all().delete()
            for end_data in endorsements_data:
                CandidateEndorsement.objects.create(candidate=instance, **end_data)

        return instance


class CandidateObjectionSerializer(serializers.ModelSerializer):
    candidate_name = serializers.CharField(source='candidate.full_name', read_only=True)
    position_title = serializers.CharField(source='candidate.position.title', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    resolved_by_email = serializers.EmailField(source='resolved_by.email', read_only=True)

    class Meta:
        from apps.candidates.models import CandidateObjection
        model = CandidateObjection
        fields = [
            'id', 'election', 'candidate', 'candidate_name', 'position_title',
            'claimant_name', 'claimant_email', 'claimant_phone', 'claimant_citizenship_number',
            'objection_reason', 'evidence_file', 'status', 'status_display',
            'resolution_notes', 'resolved_by', 'resolved_by_email', 'resolved_at', 'created_at', 'updated_at',
        ]
        read_only_fields = ['id', 'election', 'status', 'status_display', 'resolution_notes', 'resolved_by', 'resolved_by_email', 'resolved_at', 'created_at', 'updated_at']
