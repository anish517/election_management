from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.decorators import action
from rest_framework.response import Response
from apps.candidates.models import Candidate, NominationStatus
from apps.candidates.serializers import CandidateSerializer
from apps.elections.permissions import IsElectionOfficer
from apps.audit.models import log_action

class CandidateViewSet(viewsets.ModelViewSet):
    """
    Manage candidate nominations.
    """
    serializer_class = CandidateSerializer
    
    def get_permissions(self):
        from rest_framework import permissions
        if self.action in ['id_card', 'id_cards_bulk']:
            return [permissions.AllowAny()]
        if self.action in ['approve', 'reject']:
            return [IsElectionOfficer()]
        # Anyone can view candidates or submit a nomination (if election state allows)
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        qs = Candidate.objects.filter(
            election__organization=self.request.user.organization,
            election_id=self.kwargs['election_pk']
        )
        if self.request.user.role == 'candidate':
            qs = qs.filter(email__iexact=self.request.user.email)
        return qs

    def get_serializer_context(self):
        context = super().get_serializer_context()
        if 'election_pk' in self.kwargs:
            from apps.elections.models import Election
            try:
                context['election'] = Election.objects.get(
                    id=self.kwargs['election_pk'],
                    organization=self.request.user.organization
                )
            except (Election.DoesNotExist, ValueError):
                pass
        return context

    def perform_create(self, serializer):
        from apps.elections.models import Election, ElectionCommittee, ElectionRoleAssignment
        from rest_framework.exceptions import PermissionDenied, ValidationError
        from django.db import IntegrityError
        from apps.voting.models import VoterRoll
        from apps.members.models import Member

        election = Election.objects.get(
            id=self.kwargs['election_pk'],
            organization=self.request.user.organization
        )

        user_email = self.request.user.email.strip().lower()
        payload_email = (self.request.data.get('email') or '').strip().lower()
        
        # Check if this is an Admin creating a candidate for someone else via Admin Panel
        is_admin_manual_create = (
            (self.request.user.role in ['org_admin', 'super_admin'] or getattr(self.request.user, 'is_org_admin', False))
            and payload_email
            and payload_email != user_email
            and 'first_name' in self.request.data
        )

        if is_admin_manual_create:
            # Duplicate validation check for admin manual nomination
            target_email = payload_email
            target_phone = str(self.request.data.get('contact_number') or '').strip()
            first = str(self.request.data.get('first_name') or '').strip().lower()
            last = str(self.request.data.get('last_name') or '').strip().lower()

            qs = Candidate.objects.filter(election=election).exclude(
                status=NominationStatus.WITHDRAWN
            )
            if target_email:
                existing_email = qs.filter(email__iexact=target_email).first()
                if existing_email:
                    pos_title = existing_email.position.title if existing_email.position else 'another position'
                    raise ValidationError({
                        'email': f"Candidate with email '{target_email}' is already actively nominated for '{pos_title}' in this election."
                    })
            if target_phone:
                existing_phone = qs.filter(contact_number=target_phone).first()
                if existing_phone:
                    pos_title = existing_phone.position.title if existing_phone.position else 'another position'
                    raise ValidationError({
                        'contact_number': f"Candidate with contact number '{target_phone}' is already actively nominated for '{pos_title}' in this election."
                    })
            if first and last:
                existing_name = qs.filter(first_name__iexact=first, last_name__iexact=last).first()
                if existing_name:
                    pos_title = existing_name.position.title if existing_name.position else 'another position'
                    raise ValidationError({
                        'first_name': f"Candidate '{existing_name.full_name}' is already actively nominated for '{pos_title}' in this election."
                    })

            status_val = serializer.validated_data.get('status', NominationStatus.APPROVED)
            serializer.save(
                election=election,
                status=status_val,
                reviewed_by=self.request.user if status_val == NominationStatus.APPROVED else None,
                reviewed_at=timezone.now() if status_val == NominationStatus.APPROVED else None,
                review_notes="Admin created" if status_val == NominationStatus.APPROVED else ""
            )
            return

        # Conflict of Interest Check for Self-Nomination:
        # Election Officers, Observers, Auditors, Committee Members, and Org Admins CANNOT run as candidates
        is_restricted_role = (
            self.request.user.role in ['election_officer', 'observer', 'auditor', 'org_admin', 'super_admin']
            or ElectionRoleAssignment.objects.filter(
                user=self.request.user, election=election,
                role__in=['election_officer', 'observer', 'auditor']
            ).exists()
            or ElectionCommittee.objects.filter(
                election=election, chair_email__iexact=user_email
            ).exists()
        )

        if is_restricted_role:
            raise PermissionDenied(
                "Conflict of Interest: Election Officers, Observers, Auditors, and Election Committee members are not eligible to run as candidates or submit nominations in this election."
            )

        # Single Active Nomination Check per Election:
        pos = serializer.validated_data.get('position')
        existing = Candidate.objects.filter(
            election=election,
            email__iexact=user_email,
        ).exclude(status=NominationStatus.WITHDRAWN).first()
        if existing:
            pos_title = existing.position.title if existing.position else 'another position'
            raise ValidationError({
                'detail': f"You have already submitted an active nomination for '{pos_title}' in this election. Candidates may only apply for one position per election."
            })


        try:
            voter = VoterRoll.objects.filter(election=election, email__iexact=user_email).first()
            if not voter and self.request.user.phone:
                voter = VoterRoll.objects.filter(election=election, phone=self.request.user.phone).first()

            member = Member.objects.filter(organization=election.organization, email__iexact=user_email).first()

            first_name = voter.first_name if voter else (member.first_name if member else '')
            middle_name = voter.middle_name if voter else ''
            last_name = voter.last_name if voter else (member.last_name if member else '')
            phone = voter.phone if voter else (member.phone if member else self.request.user.phone)

            # Calculate applicable fee
            pos_charge = float(pos.nominee_charge or 0.0) if pos else 0.0
            el_charge = float(election.nominee_charge or 0.0)
            ps = election.organization.payment_settings or {}
            default_fee = float(ps.get('default_nomination_fee', 0.0) or 0.0)
            fee = pos_charge if pos_charge > 0 else (el_charge if el_charge > 0 else default_fee)

            is_payment_enabled = bool(ps.get('is_payment_enabled', False))
            txn_ref = (self.request.data.get('transaction_reference') or self.request.data.get('transaction_id') or '').strip()
            receipt_url = (self.request.data.get('receipt_image_url') or self.request.data.get('receipt_url') or '').strip()
            pay_notes = (self.request.data.get('payment_notes') or '').strip()
            pay_method = self.request.data.get('payment_method') or 'static_qr_bank'

            is_payment_required = is_payment_enabled and fee > 0

            initial_payment_status = 'pending_verification' if (is_payment_required and (txn_ref or receipt_url)) else 'waived'

            candidate = serializer.save(
                election=election,
                status=NominationStatus.SUBMITTED,
                payment_status=initial_payment_status,
                email=user_email,
                first_name=first_name,
                middle_name=middle_name,
                last_name=last_name,
                contact_number=phone or '',
            )

            # If payment is active and proof provided, create Payment ledger record
            if (is_payment_required and (txn_ref or receipt_url)) or txn_ref:
                from apps.billing.models import Payment, PaymentStatus
                Payment.objects.create(
                    organization=election.organization,
                    election=election,
                    candidate=candidate,
                    user=self.request.user,
                    amount=fee if fee > 0 else 0.00,
                    payment_method=pay_method,
                    transaction_reference=txn_ref,
                    receipt_image_url=receipt_url,
                    payment_notes=pay_notes,
                    status=PaymentStatus.PENDING,
                )
        except IntegrityError:
            raise ValidationError({'error': 'You have already submitted a nomination for this position.'})

    @action(detail=True, methods=['post'])
    def approve(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        notes = request.data.get('notes', '')

        if candidate.status not in [NominationStatus.SUBMITTED, NominationStatus.UNDER_REVIEW]:
            return Response({'error': 'Can only approve submitted nominations.'}, status=400)

        candidate.status = NominationStatus.APPROVED
        candidate.reviewed_by = request.user
        candidate.review_notes = notes
        candidate.reviewed_at = timezone.now()
        candidate.save()

        log_action('candidate.approved', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk)
        })

        # 📧 Notify the candidate their nomination was approved
        from apps.notifications.tasks import send_candidate_approved_notification
        send_candidate_approved_notification.delay(str(election_pk), str(candidate.id))

        return Response(self.get_serializer(candidate).data)


    @action(detail=True, methods=['post'])
    def reject(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        notes = request.data.get('notes', '')
        
        if not notes:
            return Response({'error': 'Review notes are required for rejection.'}, status=400)
            
        candidate.status = NominationStatus.REJECTED
        candidate.reviewed_by = request.user
        candidate.review_notes = notes
        candidate.reviewed_at = timezone.now()
        candidate.save()
        
        log_action('candidate.rejected', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk)
        })
        
        return Response(self.get_serializer(candidate).data)

    @action(detail=True, methods=['post'])
    def withdraw(self, request, election_pk=None, pk=None):
        candidate = self.get_object()
        reason = request.data.get('reason', '')

        user = request.user
        user_email = user.email.strip().lower() if user.email else ''
        cand_email = candidate.email.strip().lower() if candidate.email else ''
        is_owner = bool(cand_email and cand_email == user_email)
        is_officer = user.role in ['org_admin', 'election_officer', 'super_admin'] or getattr(user, 'is_org_admin', False)

        if not (is_owner or is_officer):
            raise PermissionDenied('Only the candidate or an election officer can withdraw this nomination.')

        candidate.status = NominationStatus.WITHDRAWN
        candidate.review_notes = f"Withdrawn: {reason}" if reason else "Candidate nomination withdrawn"
        candidate.save()

        log_action('candidate.withdrawn', request.user.organization, request.user, {
            'candidate_id': str(candidate.id),
            'election_id': str(election_pk),
            'reason': reason,
        })

        from apps.notifications.services import NotificationService
        try:
            NotificationService.notify_candidate_withdrawn(candidate.election, candidate, reason=reason)
        except Exception as e:
            logger.warning(f"Failed to send candidate withdrawal notification: {e}")

        return Response(self.get_serializer(candidate).data)

    @action(detail=True, methods=['get'], permission_classes=[permissions.AllowAny], authentication_classes=[])
    def id_card(self, request, election_pk=None, pk=None):
        """
        GET /v1/elections/{election_id}/candidates/{candidate_id}/id_card/
        Renders official printable Candidate ID Card (उम्मेदवार परिचयपत्र).
        """
        from django.http import HttpResponse
        from apps.elections.models import Election

        from django.shortcuts import get_object_or_404
        try:
            election = get_object_or_404(Election, id=election_pk)
            cand = get_object_or_404(Candidate, id=pk, position__election=election)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_404_NOT_FOUND)

        org = election.organization
        org_name = org.name if org else 'Election Management'
        org_logo = election.logo_url or (org.logo_url if org else '')
        photo_url = cand.candidate_image or ''
        pos_title = cand.position.title if cand.position else 'Candidate'
        quota_label = f" ({cand.quota_name})" if cand.quota_name else ''

        qr_data = f"EMS-CAND:{cand.id.hex[:8].upper()}:{election.id}:{cand.email or cand.contact_number}"
        qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=120x120&data={qr_data}"

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>Candidate ID Card - {cand.full_name}</title>
  <style>
    @page {{
      size: 85.6mm 54mm;
      margin: 0;
    }}
    @media print {{
      body {{ margin: 0; padding: 0; background: none; }}
      .no-print {{ display: none !important; }}
      .card-wrap {{ box-shadow: none !important; margin: 0 auto; page-break-after: always; }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, sans-serif;
      background: #F1F5F9;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 24px;
      margin: 0;
    }}
    .action-bar {{
      margin-bottom: 16px;
      display: flex;
      gap: 12px;
    }}
    .btn {{
      background: #4F46E5;
      color: white;
      border: none;
      padding: 9px 18px;
      border-radius: 6px;
      font-weight: 700;
      cursor: pointer;
      font-size: 13px;
      box-shadow: 0 2px 6px rgba(79,70,229,0.3);
    }}
    .btn:hover {{ background: #4338CA; }}
    .card-wrap {{
      width: 85.6mm;
      height: 54mm;
      background: #FFFFFF;
      background-image: radial-gradient(circle at 50% 50%, rgba(99, 102, 241, 0.04) 0%, rgba(255,255,255,1) 70%);
      border-radius: 8px;
      box-shadow: 0 6px 20px rgba(0,0,0,0.12);
      border: 1.5px solid #4F46E5;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      padding: 7px 10px;
    }}
    .top-banner {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1.5px solid #4F46E5;
      padding-bottom: 4px;
    }}
    .header-left {{
      display: flex;
      align-items: center;
      gap: 7px;
    }}
    .header-logo {{
      width: 30px;
      height: 30px;
      border-radius: 4px;
      object-fit: contain;
    }}
    .org-title {{
      font-size: 9.5px;
      font-weight: 900;
      color: #312E81;
      line-height: 1.1;
      text-transform: uppercase;
      letter-spacing: 0.2px;
    }}
    .el-title {{
      font-size: 8px;
      font-weight: 700;
      color: #1E293B;
      line-height: 1.1;
    }}
    .badge-ribbon {{
      background: linear-gradient(135deg, #4F46E5, #4338CA);
      color: #FFFFFF;
      font-size: 7.5px;
      font-weight: 900;
      padding: 2.5px 6px;
      border-radius: 4px;
      letter-spacing: 0.4px;
      text-align: center;
      box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    }}
    .card-body {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 7px;
      flex: 1;
      padding: 3px 0;
    }}
    .photo-col {{
      width: 44px;
      height: 52px;
      flex-shrink: 0;
    }}
    .photo-box {{
      width: 44px;
      height: 52px;
      border-radius: 4px;
      border: 1.2px solid #6366F1;
      object-fit: cover;
      background: #F8FAFC;
    }}
    .candidate-info {{
      flex: 1;
      min-width: 0;
    }}
    .cand-name {{
      font-size: 11.5px;
      font-weight: 900;
      color: #0F172A;
      margin-bottom: 2px;
      line-height: 1.15;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }}
    .cand-id-pill {{
      display: inline-block;
      background: #EEF2FF;
      color: #3730A3;
      border: 1px solid #C7D2FE;
      border-radius: 4px;
      font-size: 7.5px;
      font-weight: 800;
      padding: 1px 5px;
      margin-bottom: 3px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      max-width: 100%;
    }}
    .meta-grid {{
      display: grid;
      grid-template-columns: 1fr;
      gap: 1.5px;
      font-size: 7px;
      color: #334155;
    }}
    .meta-item {{
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }}
    .meta-label {{
      font-weight: bold;
      color: #64748B;
    }}
    .status-verified {{
      font-size: 7px;
      font-weight: 800;
      color: #059669;
      margin-top: 2px;
      display: flex;
      align-items: center;
      gap: 2px;
    }}
    .qr-container {{
      display: flex;
      flex-direction: column;
      align-items: center;
      text-align: center;
      flex-shrink: 0;
    }}
    .qr-code {{
      width: 44px;
      height: 44px;
      border: 1px solid #CBD5E1;
      border-radius: 4px;
      padding: 1px;
      background: white;
    }}
    .qr-text {{
      font-size: 5.5px;
      font-weight: bold;
      color: #64748B;
      margin-top: 2px;
      letter-spacing: 0.3px;
    }}
    .card-footer {{
      border-top: 1px dashed #CBD5E1;
      padding-top: 3px;
      display: flex;
      justify-content: space-between;
      align-items: flex-end;
    }}
    .footer-stamp {{
      font-size: 6.5px;
      color: #64748B;
      font-weight: 600;
      line-height: 1.2;
    }}
    .officer-sign {{
      text-align: right;
      font-size: 6.5px;
      color: #DC2626;
      font-weight: 800;
    }}
    .officer-line {{
      width: 60px;
      border-top: 1px solid #DC2626;
      margin-top: 1px;
    }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <button class="btn" onclick="window.print()">🖨️ Print / Save PDF</button>
    <button class="btn" style="background:#64748B;" onclick="window.close()">Close</button>
  </div>

  <div class="card-wrap">
    <div class="top-banner">
      <div class="header-left">
        {f'<img src="{org_logo}" class="header-logo">' if org_logo else '<div style="font-size:20px;">🏛️</div>'}
        <div>
          <div class="org-title">{org_name}</div>
          <div class="el-title">{election.title}</div>
        </div>
      </div>
      <div class="badge-ribbon">CANDIDATE ID<br><span style="font-size:6px;font-weight:normal;">उम्मेदवार परिचय</span></div>
    </div>

    <div class="card-body">
      <div class="photo-col">
        {f'<img src="{photo_url}" class="photo-box">' if photo_url else '<div class="photo-box" style="display:flex;align-items:center;justify-content:center;font-size:18px;color:#6366F1;">👤</div>'}
      </div>

      <div class="candidate-info">
        <div class="cand-name">{cand.full_name}</div>
        <div class="cand-id-pill">पद (Position): <b>{pos_title}{quota_label}</b></div>
        <div class="meta-grid">
          <div class="meta-item"><span class="meta-label">Code:</span> <b>{cand.id.hex[:8].upper()}</b></div>
          {f'<div class="meta-item"><span class="meta-label">Contact:</span> {cand.contact_number}</div>' if cand.contact_number else ''}
          {f'<div class="meta-item"><span class="meta-label">Party/Panel:</span> {cand.party_name or cand.panel_name}</div>' if (cand.party_name or cand.panel_name) else ''}
        </div>
        <div class="status-verified">✓ Approved Candidate (स्वीकृत उम्मेदवार)</div>
      </div>

      <div class="qr-container">
        <img src="{qr_url}" class="qr-code" alt="QR">
        <div class="qr-text">EMS VERIFY TOKEN</div>
      </div>
    </div>

    <div class="card-footer">
      <div class="footer-stamp">Election Management System • निर्वाचन आयोग</div>
      <div class="officer-sign">
        <div>Election Officer (निर्वाचन अधिकृत)</div>
        <div class="officer-line"></div>
      </div>
    </div>
  </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html')

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny], authentication_classes=[])
    def id_cards_bulk(self, request, election_pk=None):
        """
        GET /v1/elections/{election_id}/candidates/id_cards_bulk/
        Renders a printable sheet of all approved Candidate ID cards.
        """
        from django.http import HttpResponse
        from apps.elections.models import Election

        from django.shortcuts import get_object_or_404
        try:
            election = get_object_or_404(Election, id=election_pk)
            candidates = Candidate.objects.filter(
                position__election=election,
                status=NominationStatus.APPROVED
            ).select_related('position')
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_404_NOT_FOUND)

        org = election.organization
        org_name = org.name if org else 'Election Management'
        org_logo = election.logo_url or (org.logo_url if org else '')

        cards_html = ""
        for c in candidates:
            qr_data = f"EMS-CAND:{c.id.hex[:8].upper()}:{election.id}:{c.email or c.contact_number}"
            qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=120x120&data={qr_data}"
            pos_title = c.position.title if c.position else 'Candidate'
            quota_label = f" ({c.quota_name})" if c.quota_name else ''
            photo_url = c.candidate_image or ''

            cards_html += f"""
            <div class="card-wrap">
              <div class="top-banner">
                <div class="header-left">
                  {f'<img src="{org_logo}" class="header-logo">' if org_logo else '<div style="font-size:18px;">🏛️</div>'}
                  <div>
                    <div class="org-title">{org_name}</div>
                    <div class="el-title">{election.title}</div>
                  </div>
                </div>
                <div class="badge-ribbon">CANDIDATE ID<br><span style="font-size:5.5px;font-weight:normal;">उम्मेदवार परिचय</span></div>
              </div>

              <div class="card-body">
                <div class="photo-col">
                  {f'<img src="{photo_url}" class="photo-box">' if photo_url else '<div class="photo-box" style="display:flex;align-items:center;justify-content:center;font-size:16px;color:#6366F1;">👤</div>'}
                </div>

                <div class="candidate-info">
                  <div class="cand-name">{c.full_name}</div>
                  <div class="cand-id-pill">पद: <b>{pos_title}{quota_label}</b></div>
                  <div class="meta-grid">
                    <div class="meta-item"><span class="meta-label">Code:</span> <b>{c.id.hex[:8].upper()}</b></div>
                    {f'<div class="meta-item"><span class="meta-label">Contact:</span> {c.contact_number}</div>' if c.contact_number else ''}
                    {f'<div class="meta-item"><span class="meta-label">Party:</span> {c.party_name or c.panel_name}</div>' if (c.party_name or c.panel_name) else ''}
                  </div>
                  <div class="status-verified">✓ Approved Candidate</div>
                </div>

                <div class="qr-container">
                  <img src="{qr_url}" class="qr-code" alt="QR">
                  <div class="qr-text">EMS VERIFY</div>
                </div>
              </div>

              <div class="card-footer">
                <div class="footer-stamp">Election Management System</div>
                <div class="officer-sign">Election Officer (अधिकृत)<div class="officer-line"></div></div>
              </div>
            </div>
            """

        html = f"""<!DOCTYPE html>
<html lang="ne">
<head>
  <meta charset="UTF-8">
  <title>Batch Candidate ID Cards - {election.title}</title>
  <style>
    @page {{
      size: A4 portrait;
      margin: 10mm;
    }}
    @media print {{
      body {{ margin: 0; padding: 0; background: none; }}
      .no-print {{ display: none !important; }}
      .card-wrap {{ box-shadow: none !important; page-break-inside: avoid; }}
    }}
    * {{ box-sizing: border-box; }}
    body {{
      font-family: 'Segoe UI', 'Noto Sans Devanagari', -apple-system, sans-serif;
      background: #F8FAFC;
      padding: 20px;
      margin: 0;
    }}
    .action-bar {{
      margin-bottom: 20px;
      display: flex;
      gap: 12px;
      justify-content: center;
    }}
    .btn {{
      background: #4F46E5;
      color: white;
      border: none;
      padding: 10px 20px;
      border-radius: 6px;
      font-weight: 700;
      cursor: pointer;
      font-size: 14px;
      box-shadow: 0 2px 6px rgba(79,70,229,0.3);
    }}
    .btn:hover {{ background: #4338CA; }}
    .grid-container {{
      display: grid;
      grid-template-columns: repeat(auto-fill, 85.6mm);
      gap: 12px;
      justify-content: center;
    }}
    .card-wrap {{
      width: 85.6mm;
      height: 54mm;
      background: #FFFFFF;
      background-image: radial-gradient(circle at 50% 50%, rgba(99, 102, 241, 0.04) 0%, rgba(255,255,255,1) 70%);
      border-radius: 8px;
      border: 1.5px solid #4F46E5;
      overflow: hidden;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      position: relative;
      padding: 7px 10px;
      page-break-inside: avoid;
    }}
    .top-banner {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1.5px solid #4F46E5;
      padding-bottom: 4px;
    }}
    .header-left {{
      display: flex;
      align-items: center;
      gap: 7px;
    }}
    .header-logo {{ width: 28px; height: 28px; border-radius: 4px; object-fit: contain; }}
    .org-title {{ font-size: 9.5px; font-weight: 900; color: #312E81; line-height: 1.1; text-transform: uppercase; letter-spacing: 0.2px; }}
    .el-title {{ font-size: 8px; font-weight: 700; color: #1E293B; line-height: 1.1; }}
    .badge-ribbon {{ background: linear-gradient(135deg, #4F46E5, #4338CA); color: #FFFFFF; font-size: 7.5px; font-weight: 900; padding: 2px 6px; border-radius: 4px; letter-spacing: 0.4px; text-align: center; }}
    .card-body {{ display: flex; align-items: center; justify-content: space-between; gap: 7px; flex: 1; padding: 3px 0; }}
    .photo-col {{ width: 44px; height: 52px; flex-shrink: 0; }}
    .photo-box {{ width: 44px; height: 52px; border-radius: 4px; border: 1.2px solid #6366F1; object-fit: cover; background: #F8FAFC; }}
    .candidate-info {{ flex: 1; min-width: 0; }}
    .cand-name {{ font-size: 11px; font-weight: 900; color: #0F172A; margin-bottom: 2px; line-height: 1.15; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
    .cand-id-pill {{ display: inline-block; background: #EEF2FF; color: #3730A3; border: 1px solid #C7D2FE; border-radius: 4px; font-size: 7px; font-weight: 800; padding: 1px 4px; margin-bottom: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }}
    .meta-grid {{ display: grid; grid-template-columns: 1fr; gap: 1.5px; font-size: 7px; color: #334155; }}
    .meta-item {{ white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
    .meta-label {{ font-weight: bold; color: #64748B; }}
    .status-verified {{ font-size: 6.5px; font-weight: 800; color: #059669; margin-top: 2px; }}
    .qr-container {{ display: flex; flex-direction: column; align-items: center; text-align: center; flex-shrink: 0; }}
    .qr-code {{ width: 42px; height: 42px; border: 1px solid #CBD5E1; border-radius: 4px; padding: 1px; background: white; }}
    .qr-text {{ font-size: 5.5px; font-weight: bold; color: #64748B; margin-top: 2px; letter-spacing: 0.3px; }}
    .card-footer {{ border-top: 1px dashed #CBD5E1; padding-top: 3px; display: flex; justify-content: space-between; align-items: flex-end; }}
    .footer-stamp {{ font-size: 6.5px; color: #64748B; font-weight: 600; line-height: 1.2; }}
    .officer-sign {{ text-align: right; font-size: 6.5px; color: #DC2626; font-weight: 800; }}
    .officer-line {{ width: 55px; border-top: 1px solid #DC2626; margin-top: 1px; }}
  </style>
</head>
<body>
  <div class="action-bar no-print">
    <button class="btn" onclick="window.print()">🖨️ Print All Candidate Cards ({len(candidates)} Candidates)</button>
  </div>
  <div class="grid-container">
    {cards_html}
  </div>
</body>
</html>"""
        return HttpResponse(html, content_type='text/html')


class CandidateObjectionViewSet(viewsets.ModelViewSet):
    """
    CRUD and review for Candidate Eligibility Objections.
    """
    from rest_framework.permissions import IsAuthenticated
    permission_classes = [IsAuthenticated]
    from apps.candidates.serializers import CandidateObjectionSerializer
    serializer_class = CandidateObjectionSerializer

    def get_queryset(self):
        from apps.candidates.models import CandidateObjection
        election_pk = self.kwargs.get('election_pk')
        user = self.request.user
        qs = CandidateObjection.objects.filter(election_id=election_pk, election__organization=user.organization)

        is_officer = (
            user.role in ['org_admin', 'election_officer', 'super_admin']
            or getattr(user, 'is_org_admin', False)
        )
        if not is_officer:
            qs = qs.filter(claimant_email__iexact=user.email.strip().lower())
        return qs.order_by('-created_at')

    def perform_create(self, serializer):
        from django.utils import timezone
        from apps.elections.models import Election
        from rest_framework.exceptions import ValidationError, PermissionDenied

        user = self.request.user
        if user.role in ['observer', 'auditor']:
            raise PermissionDenied('Observers and Auditors have read-only monitoring access and cannot file candidate objections.')

        election_pk = self.kwargs.get('election_pk')
        election = Election.objects.get(id=election_pk, organization=user.organization)
        now = timezone.now()

        # Schedule Gating: Objections open after nomination closes and before candidacy claim deadline
        if election.nomination_close_at and now < election.nomination_close_at:
            raise ValidationError({'detail': 'Candidate objection window opens after nominations close.'})
        if election.candidacy_claim_date and now > election.candidacy_claim_date:
            raise ValidationError({'detail': 'Candidate objection deadline has passed.'})

        serializer.save(
            election=election,
            claimant_name=serializer.validated_data.get('claimant_name') or self.request.user.full_name or self.request.user.email,
            claimant_email=serializer.validated_data.get('claimant_email') or self.request.user.email,
        )

    @action(detail=True, methods=['post'])
    def resolve(self, request, election_pk=None, pk=None):
        """
        Election Officer resolves candidate objection (Upheld / Dismissed).
        """
        from apps.elections.permissions import IsElectionOfficer
        if not IsElectionOfficer().has_permission(request, self):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        objection = self.get_object()
        new_status = request.data.get('status')
        if new_status not in ['upheld', 'dismissed']:
            return Response({'detail': "Status must be 'upheld' or 'dismissed'."}, status=status.HTTP_400_BAD_REQUEST)

        notes = request.data.get('resolution_notes', '')
        objection.status = new_status
        objection.resolution_notes = notes
        objection.resolved_by = request.user
        objection.resolved_at = timezone.now()
        objection.save()

        # If objection is upheld, reject/disqualify the candidate
        if new_status == 'upheld':
            objection.candidate.status = NominationStatus.REJECTED
            objection.candidate.review_notes = f"Objection Upheld: {notes or objection.objection_reason}"
            objection.candidate.reviewed_by = request.user
            objection.candidate.reviewed_at = timezone.now()
            objection.candidate.save(update_fields=['status', 'review_notes', 'reviewed_by', 'reviewed_at'])

        log_action('candidate_objection.resolved', objection.election.organization, request.user, {
            'election_id': str(objection.election.id),
            'candidate_id': str(objection.candidate.id),
            'objection_id': str(objection.id),
            'status': objection.status
        })
        from apps.candidates.serializers import CandidateObjectionSerializer
        return Response(CandidateObjectionSerializer(objection).data)
