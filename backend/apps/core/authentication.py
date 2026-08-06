from rest_framework_simplejwt.authentication import JWTAuthentication

class QueryParameterTokenAuthentication(JWTAuthentication):
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
