"""
OTP Delivery Service
(doc: 20-Notification-System.md §20.1)
(doc: 09-Authentication-Security.md §9.1)
"""
import requests
import logging
from django.conf import settings
from django.core.mail import send_mail

logger = logging.getLogger(__name__)


class OTPService:
    @staticmethod
    def deliver(identifier: str, otp: str, purpose: str):
        """
        Deliver OTP via SMS (if phone) or Email.
        (doc: 20-Notification-System.md — SMS via Sparrow SMS, Email via SMTP)
        """
        message = OTPService._get_message(otp, purpose)

        if '@' in identifier:
            OTPService._send_email(identifier, otp, purpose, message)
        else:
            OTPService._send_sms(identifier, message)

    @staticmethod
    def _get_message(otp: str, purpose: str) -> str:
        messages = {
            'login': f"Your EMS login OTP is: {otp}. Valid for 5 minutes. Do not share.",
            'register': f"Your EMS registration OTP is: {otp}. Valid for 5 minutes.",
            'password_reset': f"Your EMS password reset OTP is: {otp}. Valid for 5 minutes.",
            'phone_verify': f"Your EMS phone verification OTP is: {otp}. Valid for 5 minutes.",
        }
        return messages.get(purpose, f"Your OTP is: {otp}. Valid for 5 minutes.")

    @staticmethod
    def _send_sms(phone: str, message: str):
        """
        Send SMS via Sparrow SMS (Nepal).
        (doc: 20-Notification-System.md - Sparrow SMS for Nepal, Twilio fallback)
        """
        if not settings.SPARROW_SMS_TOKEN:
            logger.warning(f"[DEV] OTP SMS to {phone}: {message}")
            return

        try:
            response = requests.post(
                'http://api.sparrowsms.com/v2/sms/',
                data={
                    'token': settings.SPARROW_SMS_TOKEN,
                    'from': settings.SPARROW_SMS_FROM,
                    'to': phone,
                    'text': message,
                },
                timeout=10,
            )
            if response.status_code != 200:
                logger.error(f"Sparrow SMS failed for {phone}: {response.text}")
        except Exception as e:
            logger.error(f"SMS delivery error for {phone}: {e}")

    @staticmethod
    def _send_email(email: str, otp: str, purpose: str, message: str):
        """Send OTP via email."""
        try:
            send_mail(
                subject='Your EMS OTP Code',
                message=message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                recipient_list=[email],
                fail_silently=False,
            )
        except Exception as e:
            logger.error(f"Email OTP delivery error for {email}: {e}")
            logger.warning(f"[DEV] OTP Email to {email}: {otp}")
