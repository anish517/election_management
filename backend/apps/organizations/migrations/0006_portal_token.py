# Generated manually for private portal access token
from django.db import migrations, models
import secrets

def populate_portal_tokens(apps, schema_editor):
    Organization = apps.get_model('organizations', 'Organization')
    for org in Organization.objects.all():
        if not org.portal_token:
            org.portal_token = secrets.token_urlsafe(12).replace('-', '').replace('_', '')[:16]
            org.save(update_fields=['portal_token'])

class Migration(migrations.Migration):

    dependencies = [
        ('organizations', '0005_prefix_url_handle'),
    ]

    operations = [
        migrations.AddField(
            model_name='organization',
            name='portal_token',
            field=models.CharField(
                blank=True,
                db_index=True,
                default='',
                help_text='Secret token for private branded portal URL (e.g. sldfe21324vfbgf)',
                max_length=64
            ),
        ),
        migrations.RunPython(populate_portal_tokens, migrations.RunPython.noop),
    ]
