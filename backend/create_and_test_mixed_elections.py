import os
import sys
import uuid
import secrets
import django
from datetime import timedelta

# Set up Django environment
sys.path.insert(0, r'f:\election_management\backend')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from django.contrib.auth import get_user_model
from django.utils import timezone
from apps.organizations.models import Organization
from apps.elections.models import Election, Position, ElectionState, ElectionMethod, VotingMethod, OnlineVotingType
from apps.candidates.models import Candidate, NominationStatus
from apps.voting.models import VoterRoll, Vote
from apps.voting.services import BallotService
from apps.results.services import TallyService

User = get_user_model()

def create_and_test_mixed_elections():
    print("=" * 80)
    print("  CREATING & TESTING 4 MIXED ELECTIONS (MOB, HYBRID, WEB, VENUE)")
    print("=" * 80)

    # 1. Organization & Admin User
    user = User.objects.filter(email='neworganization@gmail.com').first()
    if not user:
        print("ERROR: User neworganization@gmail.com not found!")
        return
    org = user.organization
    print(f"[ORG] Organization: {org.name} (ID: {org.id})")

    # Clean previous mixed test elections if created earlier with prefix MIX-TEST
    Election.objects.filter(organization=org, prefix__startswith='MXT').delete()

    configs = [
        {
            'key': 'mob',
            'title': 'Mixed Election — 1. Mobile App Only (mob)',
            'prefix': 'MXTMOB',
            'method': ElectionMethod.ONLINE,
            'online_type': OnlineVotingType.MOBILE_APP,
            'venue_name': '',
            'desc': 'Mixed election where voters can only vote via the Flutter Mobile App.'
        },
        {
            'key': 'hybrid',
            'title': 'Mixed Election — 2. Hybrid App + Web (hydrid)',
            'prefix': 'MXTHYB',
            'method': ElectionMethod.ONLINE,
            'online_type': OnlineVotingType.HYBRID,
            'venue_name': '',
            'desc': 'Mixed election accessible via both the Mobile App and Web Magic Link.'
        },
        {
            'key': 'web',
            'title': 'Mixed Election — 3. Web Based (web based)',
            'prefix': 'MXTWEB',
            'method': ElectionMethod.ONLINE,
            'online_type': OnlineVotingType.WEB_BASED,
            'venue_name': '',
            'desc': 'Mixed election where voters vote via Web Email Magic Link / OTP.'
        },
        {
            'key': 'venue',
            'title': 'Mixed Election — 4. Physical Venue Kiosk (venue)',
            'prefix': 'MXTVEN',
            'method': ElectionMethod.VENUE,
            'online_type': OnlineVotingType.MOBILE_APP,
            'venue_name': 'Central City Hall — Booth A1',
            'desc': 'Mixed election conducted at a physical polling venue using kiosk voting booths.'
        }
    ]

    symbols = {
        'nc': {
            'party': 'Nepali Congress',
            'symbol_name': 'Tree (रुख)',
            'symbol_image': 'http://127.0.0.1:8000/media/uploads/a55d6aa2-7aa7-4b8d-a5cf-48d8c7bcb651.jpg',
        },
        'uml': {
            'party': 'CPN-UML',
            'symbol_name': 'Sun (सूर्य)',
            'symbol_image': 'http://127.0.0.1:8000/media/uploads/8bccc9a4-e451-46da-98e8-eb081f156bdd.png',
        },
        'rsp': {
            'party': 'Rastriya Swatantra Party',
            'symbol_name': 'Bell (घण्टी)',
            'symbol_image': 'http://127.0.0.1:8000/media/uploads/25291573-f46e-4ae9-8a06-d4c439a68fa6.jpg',
        }
    }

    created_elections = []

    for cfg in configs:
        print(f"\n" + "-" * 70)
        print(f"Creating: {cfg['title']}")
        print(f"Delivery: method={cfg['method']}, online_type={cfg['online_type']}")

        election = Election.objects.create(
            organization=org,
            created_by=user,
            title=cfg['title'],
            prefix=cfg['prefix'],
            election_type="mixed",
            election_method=cfg['method'],
            online_type=cfg['online_type'],
            venue_name=cfg['venue_name'],
            venue_address='Ward 4, Kathmandu' if cfg['venue_name'] else '',
            require_venue_otp=False,
            total_pr_seats=5,
            pr_threshold_percent=3.0,
            pr_allocation_method="modified_sainte_lague",
            voting_start_at=timezone.now() - timedelta(hours=1),
            voting_end_at=timezone.now() + timedelta(days=7),
            state=ElectionState.VOTING_OPEN,
            contact_number='1111'
        )

        # 1. Direct FPTP Position: Mayor / President
        pos_fptp = Position.objects.create(
            election=election,
            title="Direct Constituency Representative (प्रत्यक्ष प्रतिनिधि)",
            voting_method="fptp",
            seats_available=1,
            result_order=1
        )

        # FPTP Candidates
        c1 = Candidate.objects.create(
            election=election,
            position=pos_fptp,
            first_name="Ram",
            last_name="Sharma",
            party_name=symbols['nc']['party'],
            symbol_name=symbols['nc']['symbol_name'],
            symbol_image=symbols['nc']['symbol_image'],
            status=NominationStatus.APPROVED,
            manifesto="Prosperity, good governance, and democratic integrity."
        )
        c2 = Candidate.objects.create(
            election=election,
            position=pos_fptp,
            first_name="Sita",
            last_name="Karki",
            party_name=symbols['uml']['party'],
            symbol_name=symbols['uml']['symbol_name'],
            symbol_image=symbols['uml']['symbol_image'],
            status=NominationStatus.APPROVED,
            manifesto="Economic development, infrastructure, and social justice."
        )

        # 2. Samānupātik PR Closed List Position & Candidates
        pos_pr = Position.objects.create(
            election=election,
            title="Samānupātik PR Closed List (समानुपातिक बन्द सूची)",
            voting_method="samanupatik",
            seats_available=5,
            result_order=2
        )

        pr_candidates_info = [
            # Nepali Congress List
            (symbols['nc']['party'], symbols['nc']['symbol_name'], symbols['nc']['symbol_image'], 1, "Bishnu Prasad", "Sharma"),
            (symbols['nc']['party'], symbols['nc']['symbol_name'], symbols['nc']['symbol_image'], 2, "Kamala Devi", "Karki"),
            (symbols['nc']['party'], symbols['nc']['symbol_name'], symbols['nc']['symbol_image'], 3, "Suresh Bahadur", "Thapa"),
            # CPN-UML List
            (symbols['uml']['party'], symbols['uml']['symbol_name'], symbols['uml']['symbol_image'], 1, "Madhav", "Joshi"),
            (symbols['uml']['party'], symbols['uml']['symbol_name'], symbols['uml']['symbol_image'], 2, "Geeta", "Shrestha"),
            (symbols['uml']['party'], symbols['uml']['symbol_name'], symbols['uml']['symbol_image'], 3, "Dipak", "Adhikari"),
            # RSP List
            (symbols['rsp']['party'], symbols['rsp']['symbol_name'], symbols['rsp']['symbol_image'], 1, "Swarnim", "Khanal"),
            (symbols['rsp']['party'], symbols['rsp']['symbol_name'], symbols['rsp']['symbol_image'], 2, "Sumana", "Tamang"),
        ]

        for party_name, sym_name, sym_img, pr_rank, fn, ln in pr_candidates_info:
            Candidate.objects.create(
                election=election,
                position=pos_pr,
                first_name=fn,
                last_name=ln,
                party_name=party_name,
                symbol_name=sym_name,
                symbol_image=sym_img,
                pr_rank=pr_rank,
                status=NominationStatus.APPROVED
            )

        # 3. Register Voters
        voters_data = [
            {'first_name': 'Anish', 'last_name': 'Tiwari', 'email': 'ahskepairawit@gmail.com', 'phone': '9800000001', 'vid': f"{cfg['prefix']}-V01", 'pin': '1111'},
            {'first_name': 'Dipendra', 'last_name': 'Shah', 'email': 'voter2@test.com', 'phone': '9800000002', 'vid': f"{cfg['prefix']}-V02", 'pin': '2222'},
            {'first_name': 'Sunita', 'last_name': 'Thapa', 'email': 'voter3@test.com', 'phone': '9800000003', 'vid': f"{cfg['prefix']}-V03", 'pin': '3333'},
            {'first_name': 'Ramesh', 'last_name': 'KC', 'email': 'voter4@test.com', 'phone': '9800000004', 'vid': f"{cfg['prefix']}-V04", 'pin': '4444'},
            {'first_name': 'Pooja', 'last_name': 'Magar', 'email': 'voter5@test.com', 'phone': '9800000005', 'vid': f"{cfg['prefix']}-V05", 'pin': '5555'},
        ]

        voter_objs = []
        for vd in voters_data:
            vr = VoterRoll.objects.create(
                election=election,
                first_name=vd['first_name'],
                last_name=vd['last_name'],
                email=vd['email'],
                phone=vd['phone'],
                voter_id=vd['vid'],
                voter_pin=vd['pin'],
                is_eligible=True
            )
            voter_objs.append(vr)

        # 4. Generate Single-Use Direct Ballot Token for ahskepairawit@gmail.com
        user_voter = voter_objs[0]
        token = secrets.token_urlsafe(32)
        user_voter.direct_ballot_token = token
        user_voter.direct_ballot_token_expires_at = timezone.now() + timedelta(hours=24)
        user_voter.direct_ballot_token_used = False
        user_voter.save(update_fields=['direct_ballot_token', 'direct_ballot_token_expires_at', 'direct_ballot_token_used'])
        magic_link = f"http://192.168.110.108:3000/#/vote/direct/{token}"

        print(f"[OK] {cfg['title']} Created!")
        print(f"     Election ID: {election.id}")
        print(f"     Voter ID: {user_voter.voter_id} | PIN: {user_voter.voter_pin}")
        if cfg['key'] in ['hybrid', 'web']:
            print(f"     Direct Magic Link: {magic_link}")

        created_elections.append({
            'cfg': cfg,
            'election': election,
            'user_voter': user_voter,
            'voter_objs': voter_objs,
            'magic_link': magic_link,
            'pos_fptp': pos_fptp,
            'c1': c1,
            'c2': c2
        })

    # ==============================================================================
    # 5. AUTOMATED BALLOT SIMULATION & TALLY VERIFICATION FOR EACH ELECTION
    # ==============================================================================
    print("\n" + "=" * 80)
    print("  SIMULATING TEST VOTES ACROSS ALL 4 MIXED ELECTIONS")
    print("=" * 80)

    for item in created_elections:
        cfg = item['cfg']
        el = item['election']
        pos_fptp = item['pos_fptp']
        c1 = item['c1']
        c2 = item['c2']
        voters = item['voter_objs']

        print(f"\n[TESTING] {cfg['title']}")

        # Simulate automated votes:
        # Voter 2: Votes Ram Sharma (NC) for FPTP, and Nepali Congress for PR
        voter_2 = voters[1]
        ballot_data_2 = {
            str(pos_fptp.id): [str(c1.id)],
            'pr_ballot': [symbols['nc']['party']]
        }
        channel = 'mobile_app' if cfg['key'] == 'mob' else ('venue_kiosk' if cfg['key'] == 'venue' else 'web_email')
        voter_2.verification_channel = channel
        voter_2.verified_at = timezone.now()
        voter_2.save(update_fields=['verification_channel', 'verified_at'])
        sess_2 = BallotService.start_session(voter_2)
        receipt_2 = BallotService.cast_vote(session_token=sess_2, ballot_data=ballot_data_2)
        print(f"  - Cast Ballot 1 (Voter: {voter_2.full_name}): Channel={channel}, Receipt={receipt_2[:16]}...")

        # Voter 3: Votes Sita Karki (CPN-UML) for FPTP, and CPN-UML for PR
        voter_3 = voters[2]
        ballot_data_3 = {
            str(pos_fptp.id): [str(c2.id)],
            'pr_ballot': [symbols['uml']['party']]
        }
        voter_3.verification_channel = channel
        voter_3.verified_at = timezone.now()
        voter_3.save(update_fields=['verification_channel', 'verified_at'])
        sess_3 = BallotService.start_session(voter_3)
        receipt_3 = BallotService.cast_vote(session_token=sess_3, ballot_data=ballot_data_3)
        print(f"  - Cast Ballot 2 (Voter: {voter_3.full_name}): Channel={channel}, Receipt={receipt_3[:16]}...")

        # Voter 4: Votes Ram Sharma (NC) for FPTP, and Rastriya Swatantra Party for PR
        voter_4 = voters[3]
        ballot_data_4 = {
            str(pos_fptp.id): [str(c1.id)],
            'pr_ballot': [symbols['rsp']['party']]
        }
        voter_4.verification_channel = channel
        voter_4.verified_at = timezone.now()
        voter_4.save(update_fields=['verification_channel', 'verified_at'])
        sess_4 = BallotService.start_session(voter_4)
        receipt_4 = BallotService.cast_vote(session_token=sess_4, ballot_data=ballot_data_4)
        print(f"  - Cast Ballot 3 (Voter: {voter_4.full_name}): Channel={channel}, Receipt={receipt_4[:16]}...")

        # Note: Voter 1 (ahskepairawit@gmail.com, V01) is kept UNVOTED so the user can test live!
        print(f"  - Voter 1 ({voters[0].email} / {voters[0].voter_id}) kept UNVOTED for user manual testing!")

        # Run Live Tally Service check
        tally = TallyService.tally_election(el)
        print(f"  [TALLY RESULT]")
        print(f"    Total Voters: {tally.get('total_voters')}, Ballots Cast: {tally.get('ballots_cast')}, Turnout: {tally.get('turnout_percentage')}%")
        
        # Check FPTP results
        fptp_res = tally.get('results', [])
        if fptp_res:
            pos_res = fptp_res[0]
            print(f"    FPTP Position: {pos_res.get('title')}")
            for c_res in pos_res.get('breakdown', []):
                print(f"      - {c_res.get('name')}: {c_res.get('score')} votes")
        
        # Check Samanupatik PR results
        sam_res = tally.get('samanupatik_results', {})
        pr_res = sam_res.get('party_results', []) if sam_res else []
        if pr_res:
            print(f"    Samānupātik PR Party Results (5 Seats Total):")
            for pr in pr_res:
                print(f"      - {pr.get('party_name')}: {pr.get('votes')} votes ({pr.get('vote_percentage')}%) -> {pr.get('seats_allocated')} seats")
                for ec in pr.get('elected_candidates', []):
                    print(f"          Elected: #{ec.get('pr_rank')} {ec.get('name')}")

    print("\n" + "=" * 80)
    print("  ALL 4 MIXED ELECTIONS READY FOR TESTING! 🎉")
    print("=" * 80)
    return created_elections

if __name__ == '__main__':
    create_and_test_mixed_elections()
