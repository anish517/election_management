import os
import django
from django.conf import settings
from django.core.mail import send_mail
import traceback

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

try:
    print(f"Testing SMTP with HOST: {settings.EMAIL_HOST}, USER: {settings.EMAIL_HOST_USER}")
    send_mail(
        'Test OTP Email',
        'This is a test email.',
        settings.DEFAULT_FROM_EMAIL,
        ['at897703@gmail.com'],
        fail_silently=False,
    )
    print("Email sent successfully!")
except Exception as e:
    print("Failed to send email:")
    traceback.print_exc()
