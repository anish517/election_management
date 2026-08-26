import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'ems_backend.settings')
django.setup()

from apps.organizations.models import Organization
from apps.users.models import User
from apps.elections.models import Election, Position
from apps.candidates.models import Candidate, NominationStatus
from apps.billing.models import Payment, PaymentStatus

def run_test():
    print("Testing Static QR Payment Backend Integration...")
    org = Organization.objects.first()
    if not org:
        print("No organization found, skipping script.")
        return

    # Update org payment settings
    org.payment_settings = {
        'is_payment_enabled': True,
        'qr_image_url': 'https://example.com/qr.png',
        'bank_name': 'Nepal Bank Limited',
        'account_name': 'EMS Organization Central',
        'account_number': '1234567890',
        'branch': 'Kathmandu',
        'wallet_type': 'fonepay',
        'wallet_id': '9800000000',
        'instructions': 'Write candidate name in remarks.',
        'default_nomination_fee': 500.0,
    }
    org.save()
    print("Updated Org Payment Settings:", org.payment_settings)

    election = org.elections.first()
    if not election:
        print("No election found, skipping.")
        return

    pos = election.positions.first()
    user = User.objects.filter(organization=org).first()

    # Create a test candidate with pending payment
    cand = Candidate.objects.create(
        election=election,
        position=pos,
        first_name="TestPay",
        last_name="Candidate",
        email="testpay@example.com",
        status=NominationStatus.SUBMITTED,
        payment_status="pending_verification",
    )

    pay = Payment.objects.create(
        organization=org,
        election=election,
        candidate=cand,
        user=user,
        amount=500.00,
        payment_method="static_qr_bank",
        transaction_reference="TXN-TEST-9988",
        receipt_image_url="https://example.com/receipt.jpg",
        payment_notes="Paid via mobile banking",
        status=PaymentStatus.PENDING,
    )
    print("Created Payment:", pay)

    # Test serializer output
    from apps.billing.serializers import PaymentSerializer
    from apps.candidates.serializers import CandidateSerializer

    p_data = PaymentSerializer(pay).data
    print("Serialized Payment Status:", p_data['status_display'])
    assert p_data['transaction_reference'] == "TXN-TEST-9988"

    c_data = CandidateSerializer(cand).data
    print("Candidate latest payment:", c_data['latest_payment'])
    assert c_data['latest_payment'] is not None
    assert c_data['latest_payment']['transaction_reference'] == "TXN-TEST-9988"

    # Test verification
    pay.status = PaymentStatus.VERIFIED
    pay.save()
    cand.payment_status = "paid"
    cand.save()

    print("Verified successfully! Cleaning up test records...")
    pay.delete()
    cand.delete()
    print("Static QR Payment Backend Test Completed Successfully!")

if __name__ == '__main__':
    run_test()
