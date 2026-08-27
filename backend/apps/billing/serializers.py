from rest_framework import serializers
from apps.billing.models import Payment, PaymentStatus, PaymentMethod

class PaymentSerializer(serializers.ModelSerializer):
    election_title = serializers.CharField(source='election.title', read_only=True)
    candidate_name = serializers.CharField(source='candidate.full_name', read_only=True)
    candidate_image = serializers.CharField(source='candidate.candidate_image', read_only=True)
    position_title = serializers.CharField(source='candidate.position.title', read_only=True)
    user_name = serializers.CharField(source='user.full_name', read_only=True)
    user_email = serializers.CharField(source='user.email', read_only=True)
    reviewed_by_email = serializers.CharField(source='reviewed_by.email', read_only=True)
    status_display = serializers.CharField(source='get_status_display', read_only=True)
    payment_method_display = serializers.CharField(source='get_payment_method_display', read_only=True)

    class Meta:
        model = Payment
        fields = [
            'id',
            'organization',
            'election',
            'election_title',
            'candidate',
            'candidate_name',
            'candidate_image',
            'position_title',
            'user',
            'user_name',
            'user_email',
            'amount',
            'currency',
            'payment_method',
            'payment_method_display',
            'transaction_reference',
            'receipt_image_url',
            'payment_notes',
            'status',
            'status_display',
            'reviewed_by',
            'reviewed_by_email',
            'reviewed_at',
            'rejection_reason',
            'correction_notes',
            'correction_history',
            'created_at',
            'updated_at',
        ]
        read_only_fields = [
            'id',
            'organization',
            'status',
            'status_display',
            'reviewed_by',
            'reviewed_by_email',
            'reviewed_at',
            'rejection_reason',
            'correction_notes',
            'correction_history',
            'created_at',
            'updated_at',
        ]


class PaymentVerificationSerializer(serializers.Serializer):
    notes = serializers.CharField(required=False, allow_blank=True, default='')


class PaymentRejectionSerializer(serializers.Serializer):
    reason = serializers.CharField(required=True, allow_blank=False)


class PaymentResubmitSerializer(serializers.Serializer):
    transaction_reference = serializers.CharField(required=True, max_length=255)
    payment_method = serializers.CharField(required=False, allow_blank=True, default='')
    receipt_image_url = serializers.CharField(required=False, allow_blank=True, default='')
    payment_notes = serializers.CharField(required=False, allow_blank=True, default='')


class PaymentCorrectionSerializer(serializers.Serializer):
    correction_notes = serializers.CharField(required=True, allow_blank=False, help_text='Describe what needs to be corrected by the candidate')
