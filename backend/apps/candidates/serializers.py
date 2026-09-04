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

from apps.elections.models import Position

class CandidateSerializer(serializers.ModelSerializer):
    position = serializers.PrimaryKeyRelatedField(queryset=Position.objects.all(), required=False)
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
        if not election and self.instance and self.instance.election:
            election = self.instance.election
        if not election and self.context.get('view') and 'election_pk' in self.context['view'].kwargs:
            from apps.elections.models import Election
            election = Election.objects.filter(id=self.context['view'].kwargs['election_pk']).first()
        
        if election:
            from apps.candidates.models import NominationStatus
            from apps.elections.models import Position

            # If Samanupatik election or candidate applying for a PR position
            is_samanupatik_election = getattr(election, 'election_type', 'fptp') == 'samanupatik'
            cand_pos = attrs.get('position') or (self.instance.position if self.instance else None)
            is_pr_position = is_samanupatik_election or (cand_pos and getattr(cand_pos, 'voting_method', '') == 'samanupatik')

            if is_pr_position:
                if not attrs.get('position') and (not self.instance or not self.instance.position):
                    pos = election.positions.filter(voting_method='samanupatik').first() or election.positions.first()
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

                max_pr_seats = getattr(election, 'total_pr_seats', 10) or 10

                # 1. Validate PR Rank Range (1 <= pr_rank <= max_pr_seats)
                pr_rank = attrs.get('pr_rank')
                if pr_rank is None and self.instance:
                    pr_rank = self.instance.pr_rank
                if pr_rank is None or pr_rank < 1:
                    pr_rank = 1
                    attrs['pr_rank'] = 1

                if pr_rank > max_pr_seats:
                    raise serializers.ValidationError({
                        "pr_rank": f"समानुपातिक बन्दसूची वरीयता क्रम १ देखि {max_pr_seats} सम्म मात्र हुनुपर्छ (PR closed-list rank #{pr_rank} exceeds the total available seats of {max_pr_seats})."
                    })

                # Validate Party Quota Limit & Duplicate Rank per Party
                party_cands_qs = Candidate.objects.filter(
                    election=election,
                    party_name__iexact=party,
                ).exclude(status__in=[NominationStatus.WITHDRAWN, NominationStatus.REJECTED])

                if self.instance and self.instance.pk:
                    party_cands_qs = party_cands_qs.exclude(pk=self.instance.pk)

                # 2. Party Quota Check: maximum active candidates for this party cannot exceed total_pr_seats
                if party_cands_qs.count() >= max_pr_seats:
                    raise serializers.ValidationError({
                        "party_name": f"दल '{party}' ले यस समानुपातिक निर्वाचनका लागि अधिकतम {max_pr_seats} जना उम्मेदवार मात्र मनोनयन गर्न सक्दछ (Party '{party}' has reached the maximum closed-list quota of {max_pr_seats} candidate(s) for this election)."
                    })

                # 3. Duplicate PR Rank within the same party
                existing_same_rank = party_cands_qs.filter(pr_rank=pr_rank).first()
                if existing_same_rank:
                    raise serializers.ValidationError({
                        "pr_rank": f"दल '{party}' मा वरीयता क्रम #{pr_rank} मा पहिले नै '{existing_same_rank.full_name}' दर्ता भइसकेका छन् (Candidate '{existing_same_rank.full_name}' is already assigned to PR rank #{pr_rank} for party '{party}')."
                    })
            else:
                if not attrs.get('position') and (not self.instance or not self.instance.position):
                    raise serializers.ValidationError({"position": "Position is required."})

            # Comprehensive Single Active Nomination Check per Election (Self & Admin)
            cand_email = (attrs.get('email') or (request.user.email if request else '')).strip().lower()
            cand_phone = (attrs.get('contact_number') or '').strip()
            first_name = (attrs.get('first_name') or '').strip().lower()
            last_name = (attrs.get('last_name') or '').strip().lower()

            qs = Candidate.objects.filter(election=election).exclude(
                status=NominationStatus.WITHDRAWN
            )
            if self.instance and self.instance.pk:
                qs = qs.exclude(pk=self.instance.pk)

            if cand_email:
                existing_email = qs.filter(email__iexact=cand_email).first()
                if existing_email:
                    pos_title = existing_email.position.title if existing_email.position else 'another position'
                    raise serializers.ValidationError(
                        f"Candidate with email '{cand_email}' is already actively nominated for '{pos_title}' in this election. Candidates may only apply for one position per election."
                    )

            if cand_phone:
                existing_phone = qs.filter(contact_number=cand_phone).first()
                if existing_phone:
                    pos_title = existing_phone.position.title if existing_phone.position else 'another position'
                    raise serializers.ValidationError(
                        f"Candidate with contact number '{cand_phone}' is already actively nominated for '{pos_title}' in this election."
                    )

            if first_name and last_name:
                existing_name = qs.filter(first_name__iexact=first_name, last_name__iexact=last_name).first()
                if existing_name:
                    pos_title = existing_name.position.title if existing_name.position else 'another position'
                    raise serializers.ValidationError(
                        f"Candidate '{existing_name.full_name}' is already actively nominated for '{pos_title}' in this election."
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
