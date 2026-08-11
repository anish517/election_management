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

def _format_bs(dt, tz_name):
    if not dt:
        return 'TBD'
    tz = zoneinfo.ZoneInfo(tz_name)
    local_dt = dt.astimezone(tz)
    bs_dt = nepali_datetime.datetime.from_datetime_datetime(local_dt)
    formatted_time = bs_dt.strftime('%I:%M %p')
    if formatted_time.startswith('00:'):
        formatted_time = '12:' + formatted_time[3:]
    return f"{bs_dt.strftime('%B %d, %Y')} at {formatted_time} (BS)"


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
        """Return list of active member emails for the election's organization."""
        from apps.members.models import Member
        emails = list(
            Member.objects.filter(
                organization=election.organization,
                membership_status='active',
                email__contains='@',
            ).values_list('email', flat=True)
        )
        logger.info(f"[Notify] Sending to {len(emails)} members for election '{election.title}'")
        return emails

    @staticmethod
    def _send_bulk(subject: str, plain_text: str, html_body: str, recipients: list):
        """Send one email to each recipient."""
        if not recipients:
            logger.warning("[Notify] No recipients found — skipping.")
            return

        sent = 0
        failed = 0
        for email in recipients:
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
            except Exception as e:
                logger.error(f"[Notify] Failed to send to {email}: {e}")
                failed += 1

        logger.info(f"[Notify] '{subject}': {sent} sent, {failed} failed.")

    # ------------------------------------------------------------------
    # Public notification methods
    # ------------------------------------------------------------------

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
        )

    @staticmethod
    def notify_candidate_approved(election, candidate):
        """Notify a candidate that their nomination was approved."""
        email = getattr(candidate.member, 'email', None) if candidate.member else None
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
