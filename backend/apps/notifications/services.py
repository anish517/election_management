"""
Election Notification Service
Sends HTML email (and SMS) notifications to members at key election lifecycle events.

In development (no EMAIL_HOST_USER set): emails print to the Django console.
In production: emails are sent via Gmail/SMTP configured in settings.
"""
import logging
import zoneinfo
from django.conf import settings
from django.core.mail import EmailMultiAlternatives
import nepali_datetime

logger = logging.getLogger(__name__)

def _format_bs(dt, tz_name=None):
    if not dt:
        return 'TBD'
    try:
        tz = zoneinfo.ZoneInfo(tz_name or 'Asia/Kathmandu')
    except Exception:
        tz = zoneinfo.ZoneInfo('Asia/Kathmandu')
    local_dt = dt.astimezone(tz)
    bs_dt = nepali_datetime.datetime.from_datetime_datetime(local_dt)
    formatted_time = bs_dt.strftime('%I:%M %p')
    if formatted_time.startswith('00:'):
        formatted_time = '12:' + formatted_time[3:]
    ad_date_str = local_dt.strftime('%b %d, %Y')
    return f"{bs_dt.strftime('%B %d, %Y')} ({ad_date_str}) at {formatted_time}"


# ---------------------------------------------------------------------------
# HTML Email Templates
# ---------------------------------------------------------------------------

def _base_email(header_color: str, icon: str, title: str, subtitle: str, body_html: str, cta_url: str = '', cta_label: str = '') -> str:
    cta_block = ''
    if cta_url and cta_label:
        cta_block = f'''
        <div style="text-align:center; margin: 28px 0 8px;">
          <a href="{cta_url}"
             style="display:inline-block; background:{header_color}; color:#fff;
                    text-decoration:none; padding:14px 32px; border-radius:10px;
                    font-weight:700; font-size:15px; letter-spacing:0.3px;">
            {cta_label}
          </a>
        </div>'''

    return f"""
    <div style="font-family:'Segoe UI',Arial,sans-serif;background:#0F172A;padding:40px 16px;min-height:100vh;">
      <div style="max-width:520px;margin:0 auto;background:#1E293B;border-radius:18px;
                  overflow:hidden;border:1px solid #334155;">

        <!-- Header -->
        <div style="background:linear-gradient(135deg,{header_color} 0%,#1E40AF 100%);padding:32px;text-align:center;">
          <div style="font-size:40px;margin-bottom:10px;">{icon}</div>
          <h1 style="color:#fff;margin:0;font-size:21px;font-weight:800;letter-spacing:-0.5px;">
            🗳️ Election Management System
          </h1>
          <p style="color:rgba(255,255,255,0.78);margin:8px 0 0;font-size:14px;">{subtitle}</p>
        </div>

        <!-- Body -->
        <div style="padding:32px;">
          <h2 style="color:#F1F5F9;margin:0 0 16px;font-size:18px;">{title}</h2>
          {body_html}
          {cta_block}
        </div>

        <!-- Footer -->
        <div style="background:#0F172A;padding:18px 32px;text-align:center;
                    border-top:1px solid #1E293B;">
          <p style="color:#475569;font-size:12px;margin:0;">
            This is an automated message from the Election Management System.<br>
            Please do not reply to this email.
          </p>
        </div>
      </div>
    </div>"""


def _info_row(icon: str, text: str) -> str:
    return f'''
    <div style="display:flex;align-items:flex-start;margin-bottom:10px;">
      <span style="font-size:16px;margin-right:10px;min-width:20px;">{icon}</span>
      <span style="color:#94A3B8;font-size:14px;line-height:1.5;">{text}</span>
    </div>'''


def _election_info_block(election) -> str:
    return f'''
    <div style="background:#0F172A;border-radius:12px;padding:20px 22px;margin:0 0 20px;">
      <div style="color:#60A5FA;font-size:12px;font-weight:700;letter-spacing:1px;
                  text-transform:uppercase;margin-bottom:12px;">Election Details</div>
      {_info_row("🏷️", f"<strong style='color:#E2E8F0;'>{election.title}</strong>")}
      {_info_row("🏢", f"<span>{election.organization.name}</span>")}
    </div>'''


# ---------------------------------------------------------------------------
# NotificationService
# ---------------------------------------------------------------------------

class NotificationService:

    @staticmethod
    def _get_member_emails(election):
        """
        Return deduplicated list of recipients strictly scoped to THIS election:
        1. Registered eligible voters in this election's VoterRoll
        2. Election Committee members assigned to this election
        3. Appointed Election Officers, Observers, and Auditors for this election
        4. Candidates in this election
        5. Election Creator & Org Admins managing this election
        (Falls back to active org members if no voters/committee are uploaded yet)
        """
        from apps.voting.models import VoterRoll
        from apps.elections.models import ElectionRoleAssignment, ElectionCommittee
        from apps.candidates.models import Candidate
        from apps.users.models import User
        from apps.members.models import Member

        recipient_set = set()

        # 1. Registered eligible voters for this specific election
        voter_emails = VoterRoll.objects.filter(
            election=election,
            is_eligible=True,
            email__contains='@',
        ).values_list('email', flat=True)
        for e in voter_emails:
            if e and e.strip():
                recipient_set.add(e.strip().lower())

        # 2. Election Committee chairs assigned to this election
        committee_emails = ElectionCommittee.objects.filter(
            election=election,
            chair_email__contains='@',
        ).values_list('chair_email', flat=True)
        for e in committee_emails:
            if e and e.strip():
                recipient_set.add(e.strip().lower())

        # 3. Election Role Assignments (officers, observers, auditors)
        assigned_user_emails = ElectionRoleAssignment.objects.filter(
            election=election,
            user__email__contains='@',
        ).values_list('user__email', flat=True)
        for e in assigned_user_emails:
            if e and e.strip():
                recipient_set.add(e.strip().lower())

        # 4. Candidates in this election
        candidate_emails = Candidate.objects.filter(
            election=election,
            email__contains='@',
        ).values_list('email', flat=True)
        for e in candidate_emails:
            if e and e.strip():
                recipient_set.add(e.strip().lower())

        # 5. Election Creator & Org Admins
        if getattr(election, 'created_by', None) and election.created_by.email:
            recipient_set.add(election.created_by.email.strip().lower())

        org_admin_emails = User.objects.filter(
            organization=election.organization,
            role='org_admin',
            email__contains='@',
        ).values_list('email', flat=True)
        for e in org_admin_emails:
            if e and e.strip():
                recipient_set.add(e.strip().lower())

        # 6. Fallback: If no voters or committee members are registered yet, notify active org members
        if not voter_emails.exists() and not committee_emails.exists() and not assigned_user_emails.exists():
            member_emails = Member.objects.filter(
                organization=election.organization,
                membership_status='active',
                email__contains='@',
            ).values_list('email', flat=True)
            for e in member_emails:
                if e and e.strip():
                    recipient_set.add(e.strip().lower())

        emails = list(recipient_set)
        logger.info(f"[Notify] Enqueueing notification for {len(emails)} scoped recipients for election '{election.title}'")
        return emails

    @staticmethod
    def _send_bulk(subject: str, plain_text: str, html_body: str, recipients: list, election=None, async_mode: bool = True):
        """Send one email to each recipient asynchronously in a background thread and log to DB."""
        if not recipients:
            logger.warning("[Notify] No recipients found — skipping.")
            return

        from apps.notifications.models import EmailBroadcastLog, EmailBroadcastStatus
        from django.utils import timezone

        created_logs = []
        if election and getattr(election, 'organization', None):
            for email in recipients:
                try:
                    log_entry = EmailBroadcastLog.objects.create(
                        organization=election.organization,
                        election=election,
                        recipient_email=email,
                        subject=subject,
                        body_html=html_body,
                        status=EmailBroadcastStatus.QUEUED,
                    )
                    created_logs.append(log_entry)
                except Exception:
                    pass

        def _worker(recip_list, log_entries):
            sent = 0
            failed = 0
            for idx, email in enumerate(recip_list):
                log_obj = log_entries[idx] if idx < len(log_entries) else None
                try:
                    msg = EmailMultiAlternatives(
                        subject=subject,
                        body=plain_text,
                        from_email=settings.DEFAULT_FROM_EMAIL,
                        to=[email],
                    )
                    msg.attach_alternative(html_body, 'text/html')
                    msg.send(fail_silently=False)
                    sent += 1
                    if log_obj:
                        log_obj.status = EmailBroadcastStatus.SENT
                        log_obj.sent_at = timezone.now()
                        log_obj.save(update_fields=['status', 'sent_at'])
                except Exception as e:
                    logger.error(f"[Notify] Failed to send to {email}: {e}")
                    failed += 1
                    if log_obj:
                        log_obj.status = EmailBroadcastStatus.FAILED
                        log_obj.error_message = str(e)
                        log_obj.save(update_fields=['status', 'error_message'])

            logger.info(f"[Notify] '{subject}': {sent} sent, {failed} failed.")

        if async_mode:
            import threading
            t = threading.Thread(target=_worker, args=(list(recipients), created_logs), daemon=True)
            t.start()
        else:
            _worker(list(recipients), created_logs)

    # ------------------------------------------------------------------
    # Public notification methods
    # ------------------------------------------------------------------

    @staticmethod
    def send_custom_email(to_email: str, subject: str, election, body_html: str):
        """Send a one-off custom email from the Admin portal."""
        html_payload = _base_email(
            header_color=election.primary_color,
            icon="📢",
            title="Important Announcement",
            subtitle=election.title,
            body_html=f"<div style='font-size:15px;line-height:1.6;color:#E2E8F0;'>{body_html}</div>"
        )
        msg = EmailMultiAlternatives(
            subject=subject,
            body="Please view this email in an HTML-compatible client.",
            from_email=settings.DEFAULT_FROM_EMAIL,
            to=[to_email],
        )
        msg.attach_alternative(html_payload, 'text/html')
        msg.send(fail_silently=False)

    @staticmethod
    def notify_nomination_open(election):
        """Nominations are now open — invite all members to nominate."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"

        tz = zoneinfo.ZoneInfo(election.organization.timezone)
        nom_close = _format_bs(election.nomination_close_at, election.organization.timezone)

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          Nominations are now open for <strong style="color:#E2E8F0;">{election.title}</strong>.
          If you wish to run for a position, please submit your nomination before the deadline.
        </p>
        {_election_info_block(election)}
        {_info_row("📅", f"Nomination deadline: <strong style='color:#E2E8F0;'>{nom_close}</strong>")}
        {_info_row("📋", "Log in to the EMS Portal to nominate yourself or view candidates.")}
        '''

        html = _base_email(
            header_color='#7C3AED',
            icon='📋',
            title='Nominations Are Now Open!',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='View Election & Nominate →',
        )

        NotificationService._send_bulk(
            subject=f'📋 Nominations Open — {election.title}',
            plain_text=f"Nominations are open for '{election.title}'. Deadline: {nom_close}. Visit {election_url} to nominate.",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_voting_open(election):
        """Voting is now open — send 'Go Vote!' blast to all members."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"

        tz = zoneinfo.ZoneInfo(election.organization.timezone)
        voting_end = _format_bs(election.voting_end_at, election.organization.timezone)

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The polls are open for <strong style="color:#E2E8F0;">{election.title}</strong>!
          Cast your vote securely through the EMS Portal before voting closes.
        </p>
        {_election_info_block(election)}
        {_info_row("⏰", f"Voting closes: <strong style='color:#F59E0B;'>{voting_end}</strong>")}
        {_info_row("🔒", "Your vote is confidential and securely recorded.")}
        {_info_row("📱", "You can vote from your phone, tablet, or computer.")}
        '''

        html = _base_email(
            header_color='#059669',
            icon='🗳️',
            title='Voting Is Now Open — Cast Your Vote!',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='Vote Now →',
        )

        NotificationService._send_bulk(
            subject=f'🗳️ Voting Is Open — {election.title}',
            plain_text=f"Voting is now open for '{election.title}'. Closes: {voting_end}. Vote at {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_voting_closed(election):
        """Voting has closed — inform members, results coming soon."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The voting period for <strong style="color:#E2E8F0;">{election.title}</strong> has now ended.
          Thank you to everyone who participated! Results are currently being tallied
          and will be published shortly.
        </p>
        {_election_info_block(election)}
        {_info_row("⚙️", "Votes are being counted automatically.")}
        {_info_row("📊", "You will receive another email when results are published.")}
        '''

        html = _base_email(
            header_color='#DC2626',
            icon='🔒',
            title='Voting Has Closed',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='View Election →',
        )

        NotificationService._send_bulk(
            subject=f'🔒 Voting Closed — {election.title}',
            plain_text=f"Voting has closed for '{election.title}'. Results are being tallied. Visit {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_results_published(election):
        """Final results are published — share with all members."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        results_url = f"{frontend_url}/elections/{election.id}"

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The official results for <strong style="color:#E2E8F0;">{election.title}</strong>
          have been published. Click below to view the full results including winner announcements
          and vote tallies.
        </p>
        {_election_info_block(election)}
        {_info_row("🏆", "Winners have been officially confirmed.")}
        {_info_row("📊", "Full vote counts and breakdowns are now available.")}
        '''

        html = _base_email(
            header_color='#D97706',
            icon='🏆',
            title='Election Results Are Published!',
            subtitle=election.title,
            body_html=body,
            cta_url=results_url,
            cta_label='View Official Results →',
        )

        NotificationService._send_bulk(
            subject=f'🏆 Results Published — {election.title}',
            plain_text=f"Results for '{election.title}' are now published. View at {results_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_candidate_approved(election, candidate):
        """Notify a candidate that their nomination was approved."""
        email = getattr(candidate, 'email', None) or (getattr(candidate.member, 'email', None) if getattr(candidate, 'member', None) else None)
        if not email or '@' not in email:
            logger.warning(f"[Notify] No email for candidate {candidate.id} — skipping approval notification.")
            return

        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          Congratulations! Your nomination for
          <strong style="color:#E2E8F0;">{candidate.position.title}</strong>
          in <strong style="color:#E2E8F0;">{election.title}</strong> has been
          <span style="color:#34D399;font-weight:700;">approved</span>.
          You are now an official candidate!
        </p>
        {_election_info_block(election)}
        {_info_row("🏅", f"Position: <strong style='color:#E2E8F0;'>{candidate.position.title}</strong>")}
        {_info_row("📢", "Share this news with your supporters!")}
        '''

        html = _base_email(
            header_color='#059669',
            icon='✅',
            title='Your Nomination Has Been Approved!',
            subtitle=f'Candidate for {candidate.position.title}',
            body_html=body,
            cta_url=election_url,
            cta_label='View Your Candidacy →',
        )

        try:
            msg = EmailMultiAlternatives(
                subject=f'✅ Nomination Approved — {election.title}',
                body=f"Your nomination for {candidate.position.title} in '{election.title}' has been approved!",
                from_email=settings.DEFAULT_FROM_EMAIL,
                to=[email],
            )
            msg.attach_alternative(html, 'text/html')
            msg.send(fail_silently=False)
            logger.info(f"[Notify] Candidate approval sent to {email}")
        except Exception as e:
            logger.error(f"[Notify] Failed to send candidate approval to {email}: {e}")

    @staticmethod
    def notify_voter_list_published(election):
        """Notify members that the voter list is published and claim window is open."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"

        claim_deadline = _format_bs(election.voter_list_claim_date, getattr(election.organization, 'timezone', None))

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The initial voter roll for <strong style="color:#E2E8F0;">{election.title}</strong>
          has been published. Please review your details and submit any claims or corrections before the deadline.
        </p>
        {_election_info_block(election)}
        {_info_row("📋", f"Claim / Objection Deadline: <strong style='color:#F59E0B;'>{claim_deadline}</strong>")}
        {_info_row("🔍", "Log in to check your voter eligibility and registration status.")}
        '''

        html = _base_email(
            header_color='#2563EB',
            icon='📜',
            title='Voter List Published — Review Your Details',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='Check Voter Roll →',
        )

        NotificationService._send_bulk(
            subject=f'📜 Voter List Published — {election.title}',
            plain_text=f"The voter roll for '{election.title}' is published. Review claims before: {claim_deadline}. Visit {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_final_voter_list_published(election):
        """Notify members that the final certified voter list is published and locked."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"
        tz = getattr(election.organization, 'timezone', None)
        nom_open = _format_bs(election.nomination_open_at, tz)

        from apps.voting.models import VoterRoll
        voter_count = VoterRoll.objects.filter(election=election, is_eligible=True).count()

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The final official voter roll for <strong style="color:#E2E8F0;">{election.title}</strong>
          has been certified and locked by the Election Committee.
        </p>
        {_election_info_block(election)}
        {_info_row("👥", f"Total Verified Voters: <strong style='color:#34D399;'>{voter_count} voters</strong>")}
        {_info_row("📋", f"Nominations Open At: <strong style='color:#60A5FA;'>{nom_open}</strong>") if nom_open else ""}
        {_info_row("🔒", "The voter list is now finalized; no further claims or additions will be accepted.")}
        '''

        html = _base_email(
            header_color='#059669',
            icon='✅',
            title='Final Voter List Published & Certified',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='View Final Voter Roll →',
        )

        NotificationService._send_bulk(
            subject=f'📜 Final Voter List Published — {election.title}',
            plain_text=f"Final voter roll for '{election.title}' is certified ({voter_count} voters). Nominations open: {nom_open}. Visit {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_final_candidates_published(election):
        """Notify members that the final list of approved candidates is published."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"
        tz = getattr(election.organization, 'timezone', None)
        voting_start = _format_bs(election.voting_start_at, tz)

        from apps.candidates.models import Candidate
        candidate_count = Candidate.objects.filter(election=election, status='approved').count()

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          The scrutiny and withdrawal period is complete. The final list of approved candidates for
          <strong style="color:#E2E8F0;">{election.title}</strong> has been officially published!
        </p>
        {_election_info_block(election)}
        {_info_row("👤", f"Approved Candidates: <strong style='color:#60A5FA;'>{candidate_count} candidates</strong>")}
        {_info_row("🗳️", f"Voting Starts At: <strong style='color:#34D399;'>{voting_start}</strong>") if voting_start else ""}
        {_info_row("📖", "Review the candidate profiles, manifestos, and qualifications on the portal.")}
        '''

        html = _base_email(
            header_color='#7C3AED',
            icon='👥',
            title='Final Approved Candidates Published',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='View Candidates & Manifestos →',
        )

        NotificationService._send_bulk(
            subject=f'👥 Final Candidate List Published — {election.title}',
            plain_text=f"Final candidate list for '{election.title}' is published ({candidate_count} candidates). Voting starts: {voting_start}. Visit {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_schedule_announcement(election):
        """Send a comprehensive election schedule announcement email to all members."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        election_url = f"{frontend_url}/elections/{election.id}"
        tz = getattr(election.organization, 'timezone', None)

        voter_claim = _format_bs(election.voter_list_claim_date, tz)
        final_voters = _format_bs(election.final_voter_list_date, tz)
        nom_open = _format_bs(election.nomination_open_at, tz)
        nom_close = _format_bs(election.nomination_close_at, tz)
        cand_final = _format_bs(election.candidacy_final_date, tz)
        voting_start = _format_bs(election.voting_start_at, tz)
        voting_end = _format_bs(election.voting_end_at, tz)

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          Official election schedule and timeline for <strong style="color:#E2E8F0;">{election.title}</strong>:
        </p>
        {_election_info_block(election)}
        {_info_row("1️⃣", f"Voter Claim Deadline: <strong>{voter_claim}</strong>")}
        {_info_row("2️⃣", f"Final Voter Roll: <strong>{final_voters}</strong>")}
        {_info_row("3️⃣", f"Nominations Period: <strong>{nom_open}</strong> to <strong>{nom_close}</strong>")}
        {_info_row("4️⃣", f"Final Candidate List: <strong>{cand_final}</strong>")}
        {_info_row("5️⃣", f"Voting Period: <strong style='color:#10B981;'>{voting_start}</strong> to <strong style='color:#F59E0B;'>{voting_end}</strong>")}
        '''

        html = _base_email(
            header_color='#6C5CE7',
            icon='📅',
            title='Official Election Timeline Announcement',
            subtitle=election.title,
            body_html=body,
            cta_url=election_url,
            cta_label='View Election Dashboard →',
        )

        NotificationService._send_bulk(
            subject=f'📅 Election Schedule — {election.title}',
            plain_text=f"Schedule announced for '{election.title}'. Voting starts: {voting_start}, closes: {voting_end}. Visit {election_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )

    @staticmethod
    def notify_results_published(election):
        """Notify all voters and members that the final certified results are published."""
        recipients = NotificationService._get_member_emails(election)
        frontend_url = getattr(settings, 'FRONTEND_URL', 'http://localhost:3000')
        results_url = f"{frontend_url}/elections/{election.id}/results"

        body = f'''
        <p style="color:#94A3B8;font-size:15px;margin:0 0 20px;line-height:1.6;">
          Official, certified election results for <strong style="color:#E2E8F0;">{election.title}</strong>
          have been finalized and published!
        </p>
        {_election_info_block(election)}
        {_info_row("🏆", "Official winners and vote counts are certified.")}
        {_info_row("📊", "View detailed seat breakdowns, vote totals, and audit records on the results portal.")}
        '''

        html = _base_email(
            header_color='#10B981',
            icon='🏆',
            title='Official Election Results Published!',
            subtitle=election.title,
            body_html=body,
            cta_url=results_url,
            cta_label='View Official Results →',
        )

        NotificationService._send_bulk(
            subject=f'🏆 Official Election Results Published — {election.title}',
            plain_text=f"Official election results for '{election.title}' are finalized! View results at {results_url}",
            html_body=html,
            recipients=recipients,
            election=election,
        )
