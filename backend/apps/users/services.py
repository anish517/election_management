"""
OTP Delivery Service
(doc: 20-Notification-System.md §20.1)
(doc: 09-Authentication-Security.md §9.1)
"""
import requests
import logging
from django.conf import settings
from django.core.mail import send_mail, EmailMultiAlternatives

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
        """Send OTP via email with an HTML template."""
        purpose_labels = {
            'login': 'Login Verification',
            'register': 'Account Registration',
            'password_reset': 'Password Reset',
            'phone_verify': 'Phone Verification',
        }
        subject_label = purpose_labels.get(purpose, 'Verification')

        html_body = f"""
        <div style="font-family: 'Segoe UI', Arial, sans-serif; background: #0F172A; padding: 20px 12px; min-height: 100vh;">
          <div style="max-width: 480px; margin: 0 auto; background: #1E293B; border-radius: 16px; overflow: hidden; border: 1px solid #334155;">
            <div style="background: linear-gradient(135deg, #1E40AF 0%, #3B82F6 100%); padding: 24px 20px; text-align: center;">
              <h1 style="color: white; margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.5px;">🗳️ Election Management System</h1>
              <p style="color: rgba(255,255,255,0.75); margin: 8px 0 0; font-size: 14px;">{subject_label}</p>
            </div>
            <div style="padding: 24px 16px; text-align: center;">
              <p style="color: #94A3B8; font-size: 15px; margin: 0 0 20px;">Your One-Time Password is:</p>
              <div style="background: #0F172A; border: 2px dashed #3B82F6; border-radius: 12px; padding: 16px 20px; display: inline-block; margin-bottom: 24px;">
                <span style="font-size: 32px; font-weight: 800; letter-spacing: 8px; color: #60A5FA; font-family: monospace;">{otp}</span>
              </div>
              <p style="color: #64748B; font-size: 13px; margin: 0;">⏱ This code expires in <strong style="color: #94A3B8;">5 minutes</strong>.</p>
              <p style="color: #64748B; font-size: 13px; margin: 8px 0 0;">🔒 Do not share this code with anyone.</p>
            </div>
            <div style="background: #0F172A; padding: 16px 32px; text-align: center;">
              <p style="color: #334155; font-size: 12px; margin: 0;">If you did not request this code, please ignore this email.</p>
            </div>
          </div>
        </div>
        """

        try:
            email_msg = EmailMultiAlternatives(
                subject=f'Your EMS OTP – {subject_label}',
                body=message,
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=[email],
            )
            email_msg.attach_alternative(html_body, 'text/html')
            email_msg.send(fail_silently=False)
        except Exception as e:
            logger.error(f"Email OTP delivery error for {email}: {e}")
            logger.warning(f"[DEV] OTP Email to {email}: {otp}")
