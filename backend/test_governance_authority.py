import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.organizations.models import Organization
from apps.users.models import User
from apps.elections.models import Election, ElectionState, ElectionRoleAssignment
from rest_framework.test import APIRequestFactory, force_authenticate
from apps.elections.views import ElectionViewSet
from apps.organizations.views import OrganizationView

def test_transparency_and_governance():
    print("\n--- Testing Transparency & Governance Authority ---")
    
    # 1. Get or create test organization
    org = Organization.objects.first()
    if not org:
        print("No organization found.")
        return

    admin_user = User.objects.filter(organization=org, role='org_admin').first()
    officer_user = User.objects.filter(organization=org, role='election_officer').first()

    if not admin_user:
        admin_user = User.objects.create_user(
            email='test_admin_gov@test.com',
            password='Password123!',
            organization=org,
            role='org_admin'
        )
    if not officer_user:
        officer_user = User.objects.create_user(
            email='test_officer_gov@test.com',
            password='Password123!',
            organization=org,
            role='election_officer'
        )

    factory = APIRequestFactory()

    # 2. Test saving Organization Election Rules
    print("Step 1: Updating Organization Rules (Transparency & Governance)...")
    org_view = OrganizationView.as_view()
    req = factory.patch('/api/v1/organization/', {
        'default_result_visibility': 'public',
        'election_officers_can_publish': False
    }, format='json')
    force_authenticate(req, user=admin_user)
    resp = org_view(req)
    print(f"Update Settings Response: {resp.status_code}, data: {resp.data}")

    org.refresh_from_db()
    assert org.default_result_visibility == 'public', f"Expected 'public', got {org.default_result_visibility}"
    assert org.election_officers_can_publish == False, f"Expected False, got {org.election_officers_can_publish}"
    print("✅ Organization settings updated and persisted successfully.")

    # 3. Test creating election inherits default_result_visibility
    print("\nStep 2: Testing new election inherits default_result_visibility...")
    election_view = ElectionViewSet.as_view({'post': 'create'})
    req_el = factory.post('/api/v1/elections/', {
        'title': 'Governance Test Election'
    }, format='json')
    force_authenticate(req_el, user=admin_user)
    resp_el = election_view(req_el)
    print(f"Create Election Response: {resp_el.status_code}")
    election_id = resp_el.data['id']
    election = Election.objects.get(id=election_id)
    assert election.results_visibility == 'public', f"Expected 'public', got {election.results_visibility}"
    print(f"✅ Created election inherited default_result_visibility: {election.results_visibility}")

    # Assign officer to election
    ElectionRoleAssignment.objects.get_or_create(
        user=officer_user,
        election=election,
        role='election_officer'
    )
    election.state = ElectionState.VOTING_CLOSED
    election.save()

    # 4. Test when election_officers_can_publish is False -> Officer blocked from publishing results
    print("\nStep 3: Testing Officer blocked when election_officers_can_publish = False...")
    advance_view = ElectionViewSet.as_view({'post': 'advance_state'})
    req_adv = factory.post(f'/api/v1/elections/{election.id}/advance_state/', {
        'state': 'results_provisional'
    }, format='json')
    force_authenticate(req_adv, user=officer_user)
    resp_adv = advance_view(req_adv, pk=str(election.id))
    print(f"Officer publish attempt response: {resp_adv.status_code}, body: {resp_adv.data}")
    assert resp_adv.status_code == 403, f"Expected 403 Forbidden, got {resp_adv.status_code}"
    print("✅ Officer successfully blocked by governance authority policy.")

    # 5. Test when election_officers_can_publish is True -> Officer allowed to publish results
    print("\nStep 4: Enabling election_officers_can_publish = True and re-testing...")
    org.election_officers_can_publish = True
    org.save()

    req_adv2 = factory.post(f'/api/v1/elections/{election.id}/advance_state/', {
        'state': 'results_provisional'
    }, format='json')
    force_authenticate(req_adv2, user=officer_user)
    resp_adv2 = advance_view(req_adv2, pk=str(election.id))
    print(f"Officer publish attempt response: {resp_adv2.status_code}")
    assert resp_adv2.status_code == 200, f"Expected 200 OK, got {resp_adv2.status_code}"
    election.refresh_from_db()
    assert election.state == ElectionState.RESULTS_PROVISIONAL
    print("✅ Officer successfully published results when authority toggle is enabled.")

    # Cleanup test election
    election.delete()
    print("\n🎉 ALL TRANSPARENCY & GOVERNANCE TESTS PASSED!")

if __name__ == '__main__':
    test_transparency_and_governance()
