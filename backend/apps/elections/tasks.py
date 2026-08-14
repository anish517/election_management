"""
Election Celery Tasks
(doc: 07-System-Architecture.md §7.5 Election State Machine)
"""
from celery import shared_task
from django.utils import timezone
from django.db import transaction
from apps.elections.models import Election, ElectionState
from apps.audit.models import log_action


@shared_task(bind=True, max_retries=3)
def calculate_results(self, election_id):
    """
    Asynchronously runs the tally engine on a closed election and caches
    the result so the Results Screen loads instantly.
    Triggered automatically when voting_end_at is reached.
    """
    try:
        from apps.results.services import TallyService
        election = Election.objects.get(id=election_id)
        tally = TallyService.tally_election(election)
        
        # Transition state to make results visible to auditors/admins
        election.transition_to(ElectionState.RESULTS_PROVISIONAL)
        
        log_action('election.results_calculated', election.organization, None, {
            'election_id': election_id,
            'ballots_cast': tally.get('ballots_cast', 0),
        })
        return {'status': 'ok', 'election_id': election_id}
    except Election.DoesNotExist:
        return {'status': 'error', 'message': f'Election {election_id} not found'}
    except Exception as exc:
        # Retry up to 3 times with exponential backoff
        raise self.retry(exc=exc, countdown=60 * (self.request.retries + 1))


@shared_task
def transition_election_states():
    """
    Cron job that runs periodically to move elections forward in the workflow
    based on their scheduled dates.
    (doc: 07-System-Architecture.md §7.5, doc: 03-Nepal-Election-Workflow.md)
    """
    from apps.notifications.tasks import (
        send_nomination_open_notification,
        send_voting_open_notification,
        send_voting_closed_notification,
    )

    now = timezone.now()

    # 1. PUBLISHED -> NOMINATION_OPEN
    with transaction.atomic():
        elections = Election.objects.filter(
            state=ElectionState.PUBLISHED,
            nomination_open_at__lte=now
        ).select_for_update()

        for election in elections:
            election.transition_to(ElectionState.NOMINATION_OPEN)
            log_action('election.state_changed', election.organization, None, {
                'election_id': str(election.id),
                'from_state': ElectionState.PUBLISHED,
                'to_state': ElectionState.NOMINATION_OPEN,
                'reason': 'Scheduled time reached'
            })
            # 📧 Notify all members that nominations are open
            send_nomination_open_notification.delay(str(election.id))

    # 2. NOMINATION_OPEN -> NOMINATION_CLOSED
    with transaction.atomic():
        elections = Election.objects.filter(
            state=ElectionState.NOMINATION_OPEN,
            nomination_close_at__lte=now
        ).select_for_update()

        for election in elections:
            election.transition_to(ElectionState.NOMINATION_CLOSED)
            log_action('election.state_changed', election.organization, None, {
                'election_id': str(election.id),
                'from_state': ElectionState.NOMINATION_OPEN,
                'to_state': ElectionState.NOMINATION_CLOSED,
                'reason': 'Scheduled time reached'
            })
            # No notification here — next email is when voting opens

    # 3. NOMINATION_CLOSED -> VOTING_OPEN
    with transaction.atomic():
        elections = Election.objects.filter(
            state=ElectionState.NOMINATION_CLOSED,
            voting_start_at__lte=now
        ).select_for_update()

        for election in elections:
            election.transition_to(ElectionState.VOTING_OPEN)
            log_action('election.state_changed', election.organization, None, {
                'election_id': str(election.id),
                'from_state': ElectionState.NOMINATION_CLOSED,
                'to_state': ElectionState.VOTING_OPEN,
                'reason': 'Scheduled time reached'
            })
            # 📧 Notify all members to go vote!
            send_voting_open_notification.delay(str(election.id))

    # 4. VOTING_OPEN -> VOTING_CLOSED
    with transaction.atomic():
        elections = Election.objects.filter(
            state=ElectionState.VOTING_OPEN,
            voting_end_at__lte=now
        ).select_for_update()

        for election in elections:
            election.transition_to(ElectionState.VOTING_CLOSED)
            log_action('election.state_changed', election.organization, None, {
                'election_id': str(election.id),
                'from_state': ElectionState.VOTING_OPEN,
                'to_state': ElectionState.VOTING_CLOSED,
                'reason': 'Scheduled time reached'
            })
            # 📧 Notify members voting has closed & results coming soon
            send_voting_closed_notification.delay(str(election.id))
            # ⚙️ Automatically trigger tally calculation and provisional results
            calculate_results.delay(str(election.id))

    # 5. RESULTS_PROVISIONAL -> RESULTS_FINAL (Automatic when dispute/contest deadline passes)
    with transaction.atomic():
        from apps.notifications.tasks import send_results_published_notification
        elections = Election.objects.filter(
            state=ElectionState.RESULTS_PROVISIONAL,
            result_contest_deadline__isnull=False,
            result_contest_deadline__lte=now
        ).select_for_update()

        for election in elections:
            election.transition_to(ElectionState.RESULTS_FINAL)
            log_action('election.state_changed', election.organization, None, {
                'election_id': str(election.id),
                'from_state': ElectionState.RESULTS_PROVISIONAL,
                'to_state': ElectionState.RESULTS_FINAL,
                'reason': 'Result contest deadline passed — results finalized'
            })
            # 📧 Notify members that final official results are published
            send_results_published_notification.delay(str(election.id))

