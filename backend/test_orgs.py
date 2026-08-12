from apps.organizations.models import Organization
for o in Organization.objects.filter(name='New organization'):
    print(o.id, o.name)
