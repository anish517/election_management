"""
Cursor-based pagination for all list endpoints.
(doc: 21-REST-API-Documentation.md §21.13)
"""
from rest_framework.pagination import CursorPagination as DRFCursorPagination


class CursorPagination(DRFCursorPagination):
    page_size = 25
    max_page_size = 100
    page_size_query_param = 'page_size'
    ordering = '-created_at'
