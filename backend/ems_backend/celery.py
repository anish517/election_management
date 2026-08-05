import os
from celery import Celery
from celery.schedules import crontab

# Set the default Django settings module for the 'celery' program.
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')

app = Celery('ems_backend')

# Using a string here means the worker doesn't have to serialize
# the configuration object to child processes.
app.config_from_object('django.conf:settings', namespace='CELERY')

# Load task modules from all registered Django apps.
app.autodiscover_tasks()

# Celery Beat Schedule
app.conf.beat_schedule = {
    'transition-election-states-every-1-minute': {
        'task': 'apps.elections.tasks.transition_election_states',
        'schedule': crontab(minute='*'),  # Run every minute
    },
}
