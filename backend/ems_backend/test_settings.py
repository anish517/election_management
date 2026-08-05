"""
Test Settings — overrides for running tests without Redis/external services.
"""
from ems_backend.settings import *  # noqa

# Use local memory cache — no Redis needed for tests
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    }
}

# Disable throttling in tests so auth endpoints don't need Redis
REST_FRAMEWORK['DEFAULT_THROTTLE_CLASSES'] = []

# Use SQLite for tests (fast, no server needed)
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': ':memory:',
    }
}

# Suppress logging noise in tests
LOGGING = {}
