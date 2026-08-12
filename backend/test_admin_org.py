from apps.users.models import User
u = User.objects.get(email='admin@gmail.com')
print('User Org:', u.organization.name if u.organization else 'None')
