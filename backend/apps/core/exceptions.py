"""
Custom exception handler for consistent error format.
(doc: 21-REST-API-Documentation.md §21.12 Error Format)
"""
from rest_framework.views import exception_handler
from rest_framework.response import Response
from rest_framework import status


def custom_exception_handler(exc, context):
    """
    Returns errors in the EMS standard format:
    {
        "error": {
            "code": "MACHINE_READABLE_CODE",
            "message": "Human readable message",
            "field_errors": {}
        }
    }
    """
    response = exception_handler(exc, context)

    if response is not None:
        error_data = {
            'error': {
                'code': _get_error_code(exc, response),
                'message': _get_error_message(response),
                'field_errors': _get_field_errors(response),
            }
        }
        response.data = error_data

    return response


def _get_error_code(exc, response):
    if hasattr(exc, 'default_code'):
        return exc.default_code.upper()
    if response.status_code == 401:
        return 'UNAUTHORIZED'
    if response.status_code == 403:
        # Never leak whether a resource exists for cross-tenant requests
        return 'FORBIDDEN'
    if response.status_code == 404:
        return 'NOT_FOUND'
    if response.status_code == 409:
        return 'CONFLICT'
    if response.status_code == 429:
        return 'RATE_LIMITED'
    return 'BAD_REQUEST'


def _get_error_message(response):
    data = response.data
    if isinstance(data, dict) and 'detail' in data:
        return str(data['detail'])
    return 'An error occurred.'


def _get_field_errors(response):
    data = response.data
    if isinstance(data, dict):
        return {k: v for k, v in data.items() if k != 'detail'}
    return {}
