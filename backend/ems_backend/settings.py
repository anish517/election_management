"""
EMS Backend - Django Settings
Driven by: 07-System-Architecture.md, 08-Database-Design.md, 09-Authentication-Security.md
"""
import os
import sys
from pathlib import Path
from datetime import timedelta
from decouple import config, Csv

BASE_DIR = Path(__file__).resolve().parent.parent

# ==============================================================================
# CORE SETTINGS
# ==============================================================================
SECRET_KEY = config('SECRET_KEY', default='insecure-dev-secret-key-change-in-production')
DEBUG = config('DEBUG', default=True, cast=bool)
ALLOWED_HOSTS = config('ALLOWED_HOSTS', default='localhost,127.0.0.1', cast=Csv())

# ==============================================================================
# APPLICATIONS
# ==============================================================================
DJANGO_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

THIRD_PARTY_APPS = [
    'rest_framework',
    'rest_framework_simplejwt',
    'rest_framework_simplejwt.token_blacklist',
    'corsheaders',
    'django_filters',
]

LOCAL_APPS = [
    'apps.organizations',
    'apps.users',
    'apps.audit',
    'apps.members',
    'apps.elections',
    'apps.candidates',
    'apps.voting',
    'apps.results',
    'apps.notifications',
    'apps.billing',
]

INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

# ==============================================================================
# MIDDLEWARE
# ==============================================================================
MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    # Custom: Adds org context to every request
    'apps.organizations.middleware.OrganizationContextMiddleware',
]

ROOT_URLCONF = 'ems_backend.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

WSGI_APPLICATION = 'ems_backend.wsgi.application'
ASGI_APPLICATION = 'ems_backend.asgi.application'

# ==============================================================================
# DATABASE — PostgreSQL (doc: 08-Database-Design.md)
# ==============================================================================
import dj_database_url

DATABASES = {
    'default': dj_database_url.config(
        default=config('DATABASE_URL', default='postgres://ems_user:ems_password@localhost:5432/ems_db'),
        conn_max_age=600,
    )
}

# ==============================================================================
# REDIS — Cache + Celery Broker + Channels Layer (doc: 07-System-Architecture.md)
# ==============================================================================
REDIS_URL = config('REDIS_URL', default='redis://localhost:6379/0')
USE_REDIS = config('USE_REDIS', default=False, cast=bool)

if USE_REDIS:
    CACHES = {
        'default': {
            'BACKEND': 'django_redis.cache.RedisCache',
            'LOCATION': REDIS_URL,
            'OPTIONS': {
                'CLIENT_CLASS': 'django_redis.client.DefaultClient',
            }
        }
    }
else:
    # Local memory cache — works without Redis (development only)
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        }
    }

# Celery Configuration (doc: 07-System-Architecture.md §7.7)
CELERY_BROKER_URL = REDIS_URL
CELERY_RESULT_BACKEND = REDIS_URL
CELERY_TIMEZONE = 'Asia/Kathmandu'
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_ACCEPT_CONTENT = ['json']

# Beat schedule for time-triggered state transitions (doc: 07-System-Architecture.md §7.7)
from celery.schedules import crontab
CELERY_BEAT_SCHEDULE = {
    'transition-election-states': {
        'task': 'apps.elections.tasks.transition_election_states',
        'schedule': 60.0,  # Every 60 seconds
    },
    'finalize-results': {
        'task': 'apps.results.tasks.finalize_results',
        'schedule': 300.0,  # Every 5 minutes
    },
}

# ==============================================================================
# CUSTOM USER MODEL (doc: 08-Database-Design.md §8.2 users table)
# ==============================================================================
AUTH_USER_MODEL = 'users.User'

# ==============================================================================
# PASSWORD VALIDATION — Argon2 (doc: 09-Authentication-Security.md §9.4)
# ==============================================================================
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.Argon2PasswordHasher',
    'django.contrib.auth.hashers.PBKDF2PasswordHasher',
]

AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'},
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
    {'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'},
]

# ==============================================================================
# DJANGO REST FRAMEWORK (doc: 09-Authentication-Security.md §9.3)
# ==============================================================================
REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
        'apps.core.authentication.QueryParameterTokenAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'DEFAULT_PAGINATION_CLASS': 'apps.core.pagination.CursorPagination',
    'PAGE_SIZE': 25,
    # Throttling only active when Redis is available (USE_REDIS=True in .env)
    'DEFAULT_THROTTLE_CLASSES': (
        [
            'rest_framework.throttling.AnonRateThrottle',
            'rest_framework.throttling.UserRateThrottle',
        ] if USE_REDIS else []
    ),
    'DEFAULT_THROTTLE_RATES': {
        'anon': '10/minute',
        'user': '1000/hour',
        'otp_request': '5/minute',  # doc: 09-Authentication-Security.md §9.1
        'vote_cast': '10/hour',     # Per-voter throttle
    },
    'EXCEPTION_HANDLER': 'apps.core.exceptions.custom_exception_handler',
}

# ==============================================================================
# JWT SETTINGS (doc: 09-Authentication-Security.md §9.1)
# ==============================================================================
SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(
        minutes=config('JWT_ACCESS_TOKEN_LIFETIME_MINUTES', default=15, cast=int)
    ),
    'REFRESH_TOKEN_LIFETIME': timedelta(
        days=config('JWT_REFRESH_TOKEN_LIFETIME_DAYS', default=30, cast=int)
    ),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
    'UPDATE_LAST_LOGIN': True,
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'AUTH_HEADER_TYPES': ('Bearer',),
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
}

# ==============================================================================
# CORS (doc: 09-Authentication-Security.md §9.4)
# ==============================================================================
CORS_ALLOWED_ORIGINS = config('CORS_ALLOWED_ORIGINS', default='http://localhost:3000', cast=Csv())
CORS_ALLOW_CREDENTIALS = True

# ==============================================================================
# STATIC & MEDIA FILES
# ==============================================================================
STATIC_URL = '/static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'

# ==============================================================================
# INTERNATIONALIZATION — Nepali/English (doc: 03-Nepal-Election-Workflow.md §3.4)
# ==============================================================================
LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Kathmandu'
USE_I18N = True
USE_TZ = True

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

# ==============================================================================
# EMAIL (doc: 20-Notification-System.md)
# ==============================================================================
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = config('EMAIL_HOST', default='smtp.gmail.com')
EMAIL_PORT = config('EMAIL_PORT', default=587, cast=int)
EMAIL_USE_TLS = config('EMAIL_USE_TLS', default=True, cast=bool)
EMAIL_HOST_USER = config('EMAIL_HOST_USER', default='')
EMAIL_HOST_PASSWORD = config('EMAIL_HOST_PASSWORD', default='')
DEFAULT_FROM_EMAIL = config('DEFAULT_FROM_EMAIL', default='noreply@emsplatform.com')

# ==============================================================================
# SMS (Sparrow SMS — Nepal, doc: 20-Notification-System.md)
# ==============================================================================
SPARROW_SMS_TOKEN = config('SPARROW_SMS_TOKEN', default='')
SPARROW_SMS_FROM = config('SPARROW_SMS_FROM', default='EMS')

# ==============================================================================
# FIREBASE CLOUD MESSAGING (doc: 20-Notification-System.md)
# ==============================================================================
FCM_SERVER_KEY = config('FCM_SERVER_KEY', default='')

# ==============================================================================
# APP-SPECIFIC SETTINGS
# ==============================================================================
# OTP settings (doc: 09-Authentication-Security.md §9.1)
OTP_EXPIRY_SECONDS = 300          # 5 minutes
OTP_MAX_ATTEMPTS_PER_WINDOW = 5   # 5 requests per 15 min
OTP_WINDOW_SECONDS = 900          # 15 minutes

# Organization trial settings (doc: 11-Organization-Management.md §11.2)
ORG_TRIAL_DAYS = 14
ORG_TRIAL_VOTER_CAP = 50

# Retention defaults (doc: 03-Nepal-Election-Workflow.md §3.6)
DEFAULT_DATA_RETENTION_YEARS = 7

# Frontend URL for email links
FRONTEND_URL = config('FRONTEND_URL', default='http://localhost:3000')

# Logging — ballot request bodies are EXCLUDED (doc: 09-Authentication-Security.md §9.5)
LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'formatters': {
        'verbose': {
            'format': '{levelname} {asctime} {module} {message}',
            'style': '{',
        },
    },
    'handlers': {
        'console': {
            'class': 'logging.StreamHandler',
            'formatter': 'verbose',
        },
    },
    'root': {
        'handlers': ['console'],
        'level': 'INFO',
    },
    'loggers': {
        'django': {
            'handlers': ['console'],
            'level': 'INFO',
            'propagate': False,
        },
        'apps.voting': {
            # Extra care: voting module logs actions ONLY, never ballot content
            'handlers': ['console'],
            'level': 'WARNING',
            'propagate': False,
        },
    },
}
