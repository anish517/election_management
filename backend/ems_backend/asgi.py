"""
ASGI config for ems_backend - supports Django Channels for WebSockets
(doc: 07-System-Architecture.md §7.6 Real-Time Layer)
"""
import os
from django.core.asgi import get_asgi_application

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')

django_asgi_app = get_asgi_application()

# Channels routing will be added in Phase 5 (Real-time)
application = django_asgi_app
