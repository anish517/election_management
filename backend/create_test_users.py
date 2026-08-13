"""
create_test_users.py
Run with: python create_test_users.py

Creates one test account for each role in the first available organization.
"""
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.users.models import User, UserRole
from apps.organizations.models import Organization

org = Organization.objects.first()
if not org:
    print("ERROR: No organization found. Register one first via the app.")
    exit(1)

print(f"\nUsing organization: {org.name} (id={org.id})\n")

TEST_USERS = [
    ('observer@test.com',       'Test@1234', UserRole.OBSERVER),
    ('auditor@test.com',        'Test@1234', UserRole.AUDITOR),
    ('voter2@test.com',         'Test@1234', UserRole.VOTER),
    ('candidate2@test.com',     'Test@1234', UserRole.CANDIDATE),
]

for email, password, role in TEST_USERS:
    if User.objects.filter(email=email).exists():
        u = User.objects.get(email=email)
        print(f"  ALREADY EXISTS  {role:20s}  {email}")
    else:
        u = User.objects.create_user(
            email=email,
            password=password,
            organization=org,
            role=role,
        )
        print(f"  CREATED         {role:20s}  {email}")

print("\nDone! All test users ready.\n")
print("=" * 55)
print(f"{'ROLE':<22} {'EMAIL':<28} PASSWORD")
print("-" * 55)
print(f"{'org_admin':<22} (use your existing org admin)  Test@1234")
for email, password, role in TEST_USERS:
    print(f"  {role:<20} {email:<28} {password}")
print("  election_officer      (create via Election Committee screen)")
print("=" * 55)
print("\nNOTE: voter/candidate OTP login — use email above, OTP will")
print("  be sent (check backend terminal for the OTP in dev mode).")
