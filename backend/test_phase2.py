import requests
import json
import sys

BASE_URL = 'http://127.0.0.1:8000/v1'

def print_step(title):
    print(f"\n{'='*50}\n{title}\n{'='*50}")

def print_res(resp):
    try:
        print(json.dumps(resp.json(), indent=2))
    except:
        print(resp.text)

# 1. Register a fresh org admin for the test
print_step("1. Register New Org & Admin")
res = requests.post(f"{BASE_URL}/auth/register/", json={
    "email": "testadmin2@sacco.com",
    "password": "Admin@12345",
    "org_name": "Phase 2 Test Org",
    "org_type": "cooperative"
})
if res.status_code in [400, 409] or "email" in res.text.lower():
    res = requests.post(f"{BASE_URL}/auth/login/", json={
        "email_or_phone": "testadmin2@sacco.com",
        "password": "Admin@12345"
    })
print_res(res)
token = res.json().get('access')
if not token:
    print("Failed to get token!")
    sys.exit(1)

headers = {"Authorization": f"Bearer {token}"}

# 2. Create Members
print_step("2. Create Members (Voters & Candidates)")
member1_res = requests.post(f"{BASE_URL}/members/", headers=headers, json={
    "member_code": "M-001",
    "full_name": "Alice Smith",
    "email": "alice@sacco.com",
    "membership_status": "active"
})
print("Member 1:")
print_res(member1_res)
member1_id = member1_res.json()['id']

member2_res = requests.post(f"{BASE_URL}/members/", headers=headers, json={
    "member_code": "M-002",
    "full_name": "Bob Jones",
    "email": "bob@sacco.com",
    "membership_status": "active"
})
print("Member 2:")
print_res(member2_res)
member2_id = member2_res.json()['id']

# 3. Create an Election
print_step("3. Create Election (Draft)")
election_res = requests.post(f"{BASE_URL}/elections/", headers=headers, json={
    "title": "Board Election 2027",
    "description": "Electing the new board members.",
    "is_secret_ballot": True
})
print_res(election_res)
election_id = election_res.json()['id']

# 4. Add Positions
print_step("4. Add Positions to Election")
pos_res = requests.post(f"{BASE_URL}/elections/{election_id}/positions/", headers=headers, json={
    "title": "President",
    "seats_available": 1,
    "voting_method": "fptp"
})
print_res(pos_res)
position_id = pos_res.json()['id']

# 5. Create Candidates (Nominations)
print_step("5. Submit Candidate Nominations")
cand1_res = requests.post(f"{BASE_URL}/elections/{election_id}/candidates/", headers=headers, json={
    "election": election_id,
    "position": position_id,
    "member": member1_id,
    "manifesto": "I will make this SACCO great!"
})
print("Candidate 1 (Alice for President):")
print_res(cand1_res)
cand1_id = cand1_res.json()['id']

cand2_res = requests.post(f"{BASE_URL}/elections/{election_id}/candidates/", headers=headers, json={
    "election": election_id,
    "position": position_id,
    "member": member2_id,
    "manifesto": "Vote for Bob!"
})
print("Candidate 2 (Bob for President):")
print_res(cand2_res)

# 6. Approve Candidate 1
print_step("6. Approve Candidate 1")
approve_res = requests.post(f"{BASE_URL}/elections/{election_id}/candidates/{cand1_id}/approve/", headers=headers, json={
    "notes": "Looks good."
})
print_res(approve_res)

# 7. Publish Election
print_step("7. Publish Election (Draft -> Published)")
publish_res = requests.post(f"{BASE_URL}/elections/{election_id}/publish/", headers=headers)
print_res(publish_res)

# 8. Check Election History
print_step("8. Check Election State Transition History")
history_res = requests.get(f"{BASE_URL}/elections/{election_id}/history/", headers=headers)
print_res(history_res)

print("\nAll Phase 2 Integration Tests Complete!")
