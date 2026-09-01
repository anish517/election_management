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
    latest_payment = serializers.SerializerMethodField(read_only=True)
    
    class Meta:
        model = Candidate
        fields = [
            'id', 'election', 'position', 'position_title', 'quota', 'quota_name',
            'party_name', 'panel_name', 'symbol_name', 'symbol_image', 'pr_rank',
            'first_name', 'middle_name', 'last_name', 'full_name',
            'email', 'contact_number', 'gender', 'date_of_birth', 'address',
            'candidate_image', 'personal_description', 'contribution_to_org',
            'manifesto', 'status', 'payment_status', 'latest_payment',
            'documents', 'endorsements', 
            'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at'
        ]
        read_only_fields = ['id', 'election', 'reviewed_by', 'review_notes', 'reviewed_at', 'created_at', 'updated_at', 'full_name', 'latest_payment']

    def get_latest_payment(self, obj):
        payment = obj.payments.order_by('-created_at').first()
        if not payment:
            return None
        return {
            'id': str(payment.id),
            'amount': str(payment.amount),
            'currency': payment.currency,
            'payment_method': payment.payment_method,
            'payment_method_display': payment.get_payment_method_display(),
            'transaction_reference': payment.transaction_reference,
            'receipt_image_url': payment.receipt_image_url,
            'payment_notes': payment.payment_notes,
            'status': payment.status,
            'status_display': payment.get_status_display(),
            'rejection_reason': payment.rejection_reason,
            'correction_notes': payment.correction_notes or '',
            'correction_history': payment.correction_history or [],
            'created_at': payment.created_at.isoformat() if payment.created_at else None,
        }

    def validate(self, attrs):
        request = self.context.get('request')
        election = self.context.get('election') or attrs.get('election')
        
        if election:
            from apps.candidates.models import NominationStatus
            from apps.elections.models import Position

            # If Samanupatik election, ensure position and require party name
            if getattr(election, 'election_type', 'fptp') == 'samanupatik':
                if not attrs.get('position') and (not self.instance or not self.instance.position):
                    pos = election.positions.first()
                    if not pos:
                        pos = Position.objects.create(
                            election=election,
                            title="Samānupātik PR Representative (समानुपातिक प्रतिनिधि)",
                            seats_available=getattr(election, 'total_pr_seats', 10) or 10,
                            voting_method='samanupatik',
                            max_votes_per_voter=1,
                            result_order=1,
                        )
                    attrs['position'] = pos

                party = (attrs.get('party_name') or (self.instance.party_name if self.instance else '')).strip()
                if not party:
                    raise serializers.ValidationError({
                        "party_name": "Political Party affiliation (राजनीतिक दल) is strictly required for Samānupātik closed-list candidates."
                    })
                if attrs.get('pr_rank', 0) < 1:
                    attrs['pr_rank'] = 1

            if request and request.method == 'POST':
                user_email = request.user.email.strip().lower()
                existing = Candidate.objects.filter(
                    election=election,
                    email__iexact=user_email,
                ).exclude(status__in=[NominationStatus.WITHDRAWN, NominationStatus.REJECTED]).first()
                if existing:
                    pos_title = existing.position.title if existing.position else 'another position'
                    raise serializers.ValidationError(
                        f"You have already filed an active nomination for '{pos_title}' in this election. Candidates may only apply for one position per election."
                    )
        return attrs


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
