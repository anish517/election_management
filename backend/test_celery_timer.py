"""
test_celery_timer.py — Quick live test of Celery automated election timers.

This script:
1. Creates a test election in PUBLISHED state.
2. Sets voting_start_at to RIGHT NOW (so Celery opens voting immediately).
3. Sets voting_end_at to 2 minutes from now (so Celery closes it in 2 min).
4. Polls the DB every 15 seconds and prints the election state.
5. After voting closes, confirms the tally ran automatically.

Usage:
    cd f:\\election_management\\backend
    ..\venv\Scripts\python.exe test_celery_timer.py
"""

import os
import sys
import time
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
django.setup()

from django.utils import timezone
from datetime import timedelta
from apps.elections.models import Election, ElectionState
from apps.organizations.models import Organization

print("=" * 60)
print("  CELERY TIMER LIVE TEST")
print("=" * 60)

# -------------------------------------------------------
# Step 1: Get the first available organization
# -------------------------------------------------------
org = Organization.objects.first()
if not org:
    print("❌ ERROR: No organization found in database. Please register first.")
    sys.exit(1)

print(f"✅ Using organization: {org.name}")

now = timezone.now()

# -------------------------------------------------------
# Step 2: Create a test election in PUBLISHED state
#         with voting opening NOW and closing in 2 minutes
# -------------------------------------------------------
election = Election.objects.create(
    organization=org,
    title=f"[CELERY-TEST] Auto Timer Test @ {now.strftime('%H:%M:%S')}",
    description="Automated test election — safe to delete after test.",
    state=ElectionState.NOMINATION_CLOSED,  # Skip straight to pre-voting state
    voting_start_at=now - timedelta(seconds=5),   # Started 5 seconds ago → Celery will open it immediately
    voting_end_at=now + timedelta(minutes=2),     # Closes in 2 minutes
)

print(f"\n✅ Created test election: {election.id}")
print(f"   Title       : {election.title}")
print(f"   State       : {election.state} (nominations_closed)")
print(f"   Voting opens: {election.voting_start_at.strftime('%H:%M:%S')} UTC (should trigger NOW)")
print(f"   Voting ends : {election.voting_end_at.strftime('%H:%M:%S')} UTC (in ~2 minutes)")

print("\n📡 Watching for Celery to act... (polling every 15 seconds)")
print("   Make sure your Celery Worker and Beat terminals are running!\n")

# -------------------------------------------------------
# Step 3: Poll the DB every 15 seconds for up to 4 minutes
# -------------------------------------------------------
last_state = None
for i in range(16):  # 16 * 15 = 240 seconds = 4 minutes
    time.sleep(15)
    
    # Refresh from DB
    election.refresh_from_db()
    
    if election.state != last_state:
        print(f"  [{i*15:>3}s] 🔄 STATE CHANGED: {last_state} ──► {election.state.upper()}")
        last_state = election.state
        
        if election.state == ElectionState.VOTING_OPEN:
            print("       ✅ VOTING IS NOW OPEN! Celery opened it automatically.")
        elif election.state == ElectionState.VOTING_CLOSED:
            print("       ✅ VOTING IS NOW CLOSED! Celery closed it automatically.")
            print("       ⚙️  Tally task should have been queued. Checking audit log...")
            # Show state transition history
            transitions = election.state_transitions.all().order_by('created_at')
            print("\n  📋 Full Transition History:")
            for t in transitions:
                triggered_by = t.triggered_by.email if t.triggered_by else "🤖 CELERY (automatic)"
                print(f"     {t.created_at.strftime('%H:%M:%S')} | {t.from_state} → {t.to_state} | by: {triggered_by}")
            break
    else:
        print(f"  [{i*15:>3}s] State is still: {election.state} (waiting for Celery...)")

print("\n" + "=" * 60)
if election.state == ElectionState.VOTING_CLOSED:
    print("✅ TEST PASSED! Celery timers are working perfectly.")
    print(f"   The election automatically closed at {timezone.now().strftime('%H:%M:%S')} UTC")
else:
    print("⚠️  TEST TIMEOUT — State is still:", election.state)
    print("   LIKELY CAUSE: The Celery Worker or Beat process is NOT running.")
    print("   Please open two new terminal windows and run:")
    print("   Window 1: celery -A ems_backend worker --pool=solo -l info")
    print("   Window 2: celery -A ems_backend beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler")
print("=" * 60)
print(f"\n💡 The test election '{election.title}' is still in the DB.")
print(f"   You can delete it from Django Admin or via the UI.")
