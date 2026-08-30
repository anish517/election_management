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
    if isinstance(data, dict):
        if 'detail' in data:
            return str(data['detail'])
        if 'non_field_errors' in data and data['non_field_errors']:
            err = data['non_field_errors']
            return err[0] if isinstance(err, list) else str(err)
        if 'message' in data and data['message'] != 'An error occurred.':
            return str(data['message'])
        # Fall back to first field error
        for key, val in data.items():
            if key not in ('detail', 'non_field_errors', 'message'):
                if isinstance(val, list) and val:
                    first_err = str(val[0])
                    # If the error doesn't already contain the field name, prefix it
                    return first_err
                elif isinstance(val, str) and val:
                    return val
    elif isinstance(data, list) and data:
        return data[0] if isinstance(data[0], str) else str(data[0])
    return 'An error occurred.'


def _get_field_errors(response):
    data = response.data
    if isinstance(data, dict):
        return {k: v for k, v in data.items() if k not in ('detail', 'non_field_errors', 'message')}
    return {}
