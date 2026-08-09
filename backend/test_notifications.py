"""
test_notifications.py — Preview all election email notifications in the Django console.

Usage:
    cd f:\\election_management\\backend
    ..\venv\Scripts\python.exe test_notifications.py

This does NOT send real emails. It uses Django's ConsoleEmailBackend
to print the HTML directly to this terminal so you can see exactly
what members would receive.
"""
import os
import sys
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
os.environ['EMAIL_HOST_USER'] = ''  # Force console backend
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
django.setup()

# Override to console backend for this test
from django.test.utils import override_settings
from apps.elections.models import Election
from apps.notifications.services import NotificationService

election = Election.objects.first()
if not election:
    print("❌ No elections found. Please create an election first.")
    sys.exit(1)

print("=" * 70)
print(f"  Testing notifications for: {election.title}")
print(f"  Organization: {election.organization.name}")
print("=" * 70)

with override_settings(EMAIL_BACKEND='django.core.mail.backends.console.EmailBackend'):
    print("\n\n📧 [1/4] NOMINATION OPEN email:")
    print("-" * 40)
    NotificationService.notify_nomination_open(election)

    print("\n\n📧 [2/4] VOTING OPEN email:")
    print("-" * 40)
    NotificationService.notify_voting_open(election)

    print("\n\n📧 [3/4] VOTING CLOSED email:")
    print("-" * 40)
    NotificationService.notify_voting_closed(election)

    print("\n\n📧 [4/4] RESULTS PUBLISHED email:")
    print("-" * 40)
    NotificationService.notify_results_published(election)

print("\n" + "=" * 70)
print("✅ All 4 notification templates rendered successfully!")
print("   In production, these would be sent to all active members.")
print("=" * 70)
