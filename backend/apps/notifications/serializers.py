from rest_framework import serializers
from apps.notifications.models import EmailBroadcastLog


class EmailBroadcastLogSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()

    class Meta:
        model = EmailBroadcastLog
        fields = [
            'id',
            'organization',
            'election',
            'recipient_email',
            'recipient_name',
            'recipient_group',
            'subject',
            'status',
            'error_message',
            'sent_at',
            'sender',
            'sender_name',
            'created_at',
        ]
        read_only_fields = fields

    def get_sender_name(self, obj):
        if obj.sender:
            return getattr(obj.sender, 'full_name', '') or getattr(obj.sender, 'email', '') or 'Admin'
        return 'System'
