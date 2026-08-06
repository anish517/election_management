import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.users.models import User
from apps.organizations.models import Organization

def create_test_users():
    # 1. Get or create the test organization
    org, _ = Organization.objects.get_or_create(
        name="Phase 2 Test Org",
        defaults={"email": "info@testorg.com", "phone": "+1234567890"}
    )
    
    password = "Password@123"
    
    roles = [
        {"email": "admin@test.com", "role": "org_admin", "name": "Admin User"},
        {"email": "officer@test.com", "role": "election_officer", "name": "Officer User"},
        {"email": "observer@test.com", "role": "observer", "name": "Observer User"},
        {"email": "voter1@test.com", "role": "member", "name": "Standard Voter 1"},
        {"email": "voter2@test.com", "role": "member", "name": "Standard Voter 2"},
    ]
    
    print("--- Creating Test Users ---")
    for r in roles:
        # Check if user already exists
        user = User.objects.filter(email=r["email"]).first()
        if not user:
            user = User.objects.create_user(
                email=r["email"],
                password=password,
                role=r["role"],
                organization=org
            )
            print(f"✅ Created: {r['email']} | Role: {r['role']}")
        else:
            # Update password just in case
            user.set_password(password)
            user.role = r["role"]
            user.organization = org
            user.save()
            print(f"🔄 Updated: {r['email']} | Role: {r['role']}")
            
    print(f"\nAll users have the password: {password}")

if __name__ == "__main__":
    create_test_users()
