from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed


class SessionAwareJWTAuthentication(JWTAuthentication):
    """
    JWT authentication that also rejects tokens issued before the user's
    `tokens_valid_after` (set when the password is changed or reset), so other
    logged-in devices are signed out.
    """
    def get_user(self, validated_token):
        user = super().get_user(validated_token)
        cutoff = getattr(user, 'tokens_valid_after', None)
        issued_at = validated_token.get('iat')
        # Whole seconds: the token's iat has no fractional part.
        if cutoff and issued_at is not None and int(issued_at) < int(cutoff.timestamp()):
            raise AuthenticationFailed(
                'Your session ended because your password was changed. Please sign in again.',
                code='session_revoked',
            )
        return user


class QueryParameterTokenAuthentication(SessionAwareJWTAuthentication):
    """
    Looks for the JWT token in the 'token' query parameter instead of the Authorization header.
    Useful for GET requests triggered by browser file downloads (e.g. url_launcher).
    """
    def get_header(self, request):
        return None

    def authenticate(self, request):
        token = request.query_params.get('token')
        if token is None:
            return None
            
        validated_token = self.get_validated_token(token)
        return self.get_user(validated_token), validated_token
