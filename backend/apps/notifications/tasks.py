"""
Notification Celery Tasks
Fire-and-forget background tasks for each election notification event.
These are queued by the election state machine and run asynchronously
so they never slow down the state transitions.
"""
from celery import shared_task
import logging

logger = logging.getLogger(__name__)


@shared_task
def send_nomination_open_notification(election_id: str):
    try:
        from apps.elections.models import Election
        from apps.notifications.services import NotificationService
        election = Election.objects.select_related('organization').get(id=election_id)
        NotificationService.notify_nomination_open(election)
    except Exception as e:
        logger.error(f"[notify_nomination_open] Failed for election {election_id}: {e}")


@shared_task
def send_voting_open_notification(election_id: str):
    try:
        from apps.elections.models import Election
        from apps.notifications.services import NotificationService
        election = Election.objects.select_related('organization').get(id=election_id)
        NotificationService.notify_voting_open(election)
    except Exception as e:
        logger.error(f"[notify_voting_open] Failed for election {election_id}: {e}")


@shared_task
def send_voting_closed_notification(election_id: str):
    try:
        from apps.elections.models import Election
        from apps.notifications.services import NotificationService
        election = Election.objects.select_related('organization').get(id=election_id)
        NotificationService.notify_voting_closed(election)
    except Exception as e:
        logger.error(f"[notify_voting_closed] Failed for election {election_id}: {e}")


@shared_task
def send_results_published_notification(election_id: str):
    try:
        from apps.elections.models import Election
        from apps.notifications.services import NotificationService
        election = Election.objects.select_related('organization').get(id=election_id)
        NotificationService.notify_results_published(election)
    except Exception as e:
        logger.error(f"[notify_results_published] Failed for election {election_id}: {e}")

@shared_task
def send_custom_broadcast_email_task(election_id: str, subject: str, body_html: str, recipient_emails: list = None, sender_id: str = None, recipient_group: str = 'voters'):
    from django.utils import timezone
    from apps.elections.models import Election
    from apps.voting.models import VoterRoll
    from apps.notifications.models import EmailBroadcastLog, EmailBroadcastStatus
    from apps.notifications.services import NotificationService
    from apps.users.models import User

    try:
        election = Election.objects.select_related('organization').get(id=election_id)
    except Election.DoesNotExist:
        logger.error(f"[send_custom_broadcast_email_task] Election {election_id} not found.")
        return

    sender = None
    if sender_id:
        sender = User.objects.filter(id=sender_id).first()

    if recipient_emails is None:
        recipient_emails = list(
            VoterRoll.objects.filter(election=election, is_eligible=True)
            .exclude(email='')
            .values_list('email', flat=True)
        )

    for email_item in recipient_emails:
        target_email = str(email_item).strip().lower()
        if not target_email or '@' not in target_email:
            continue

        log_entry = EmailBroadcastLog.objects.create(
            organization=election.organization,
            election=election,
            recipient_email=target_email,
            subject=subject,
            body_html=body_html,
            recipient_group=recipient_group,
            status=EmailBroadcastStatus.QUEUED,
            sender=sender,
        )

        try:
            NotificationService.send_custom_email(
                to_email=target_email,
                subject=subject,
                election=election,
                body_html=body_html,
            )
            log_entry.status = EmailBroadcastStatus.SENT
            log_entry.sent_at = timezone.now()
            log_entry.error_message = ''
            log_entry.save(update_fields=['status', 'sent_at', 'error_message', 'updated_at'])
            logger.info(f"[send_custom_broadcast_email_task] Sent broadcast email to {target_email}")
        except Exception as e:
            err_msg = str(e)
            logger.error(f"[send_custom_broadcast_email_task] Failed to send to {target_email}: {err_msg}")
            log_entry.status = EmailBroadcastStatus.FAILED
            log_entry.sent_at = timezone.now()
            log_entry.error_message = err_msg
            log_entry.save(update_fields=['status', 'sent_at', 'error_message', 'updated_at'])


@shared_task
def send_candidate_approved_notification(election_id: str, candidate_id: str):
    try:
        from apps.elections.models import Election
        from apps.candidates.models import Candidate
        from apps.notifications.services import NotificationService
        election = Election.objects.select_related('organization').get(id=election_id)
        candidate = Candidate.objects.select_related('member', 'position').get(id=candidate_id)
        NotificationService.notify_candidate_approved(election, candidate)
    except Exception as e:
        logger.error(f"[notify_candidate_approved] Failed for election {election_id}, candidate {candidate_id}: {e}")
