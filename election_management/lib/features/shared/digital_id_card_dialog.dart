import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_constants.dart';

class DigitalIdCardDialog extends StatelessWidget {
  final String title;
  final String cardType; // 'voter' or 'candidate'
  final String fullName;
  final String idNumber;
  final String? councilNumber;
  final String? positionTitle;
  final String? photoUrl;
  final String? phone;
  final String electionTitle;
  final String? orgName;
  final String? orgLogo;
  final String electionId;
  final String entityId; // voter_id (PK) or candidate_id (PK)

  const DigitalIdCardDialog({
    super.key,
    this.title = 'Official Digital ID Card',
    required this.cardType,
    required this.fullName,
    required this.idNumber,
    this.councilNumber,
    this.positionTitle,
    this.photoUrl,
    this.phone,
    required this.electionTitle,
    this.orgName,
    this.orgLogo,
    required this.electionId,
    required this.entityId,
  });

  String get _printUrl {
    final baseUrl = ApiConstants.baseUrl.replaceAll('/v1', '');
    if (cardType == 'candidate') {
      return '$baseUrl/v1/elections/$electionId/candidates/$entityId/id_card/';
    }
    return '$baseUrl/v1/elections/$electionId/voters/$entityId/id_card/';
  }

  void _openPrintUrl(BuildContext context) async {
    final uri = Uri.parse(_printUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: _printUrl));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ID Card link copied to clipboard!')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _printUrl));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ID Card link copied to clipboard!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCandidate = cardType == 'candidate';
    final primaryBadgeColor = isCandidate ? const Color(0xFF6366F1) : const Color(0xFF10B981);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(18),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Dialog Bar
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryBadgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isCandidate ? Icons.badge_rounded : Icons.credit_card_rounded,
                    color: primaryBadgeColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        isCandidate ? 'उम्मेदवार आधिकारिक डिजिटल परिचयपत्र' : 'मतदाता आधिकारिक डिजिटल परिचयपत्र',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Official CR80 ID Card Visual
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCandidate ? const Color(0xFF818CF8) : const Color(0xFF34D399),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (isCandidate ? const Color(0xFF6366F1) : const Color(0xFF10B981))
                        .withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Org Logo + Names + Badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (orgLogo != null && orgLogo!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            orgLogo!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stack) => const Icon(Icons.account_balance_rounded, size: 34),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: primaryBadgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.account_balance_rounded, color: primaryBadgeColor, size: 24),
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (orgName ?? 'ELECTION COMMISSION').toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white70 : const Color(0xFF334155),
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              electionTitle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: primaryBadgeColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: primaryBadgeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isCandidate ? 'CANDIDATE ID' : 'VOTER ID',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, thickness: 1),

                  // Middle Content Section
                  if (!isCandidate) ...[
                    // ══════════════════════════════════════════════════════════
                    // PROFESSIONAL VOTER ID CARD (No Photo - Full Credential)
                    // ══════════════════════════════════════════════════════════
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Column: Voter Identity & Legal Credentials
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: primaryBadgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: primaryBadgeColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  'मतदाता परिचय नं (Voter Roll No): $idNumber',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: primaryBadgeColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (councilNumber != null && councilNumber!.isNotEmpty) ...[
                                Text(
                                  'Council / Reg No: $councilNumber',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              if (phone != null && phone!.isNotEmpty) ...[
                                Text(
                                  'सम्पर्क (Phone): $phone',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.verified_rounded, size: 14, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Statutorily Enrolled & Eligible (योग्य मतदाता)',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10B981),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Right Column: Official QR Verification + Authenticity Seal
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(Icons.qr_code_2_rounded, size: 54, color: primaryBadgeColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'VERIFY TOKEN\nडिजिटल प्रमाणीकरण',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white38 : Colors.grey.shade600,
                                height: 1.1,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    // ══════════════════════════════════════════════════════════
                    // CANDIDATE ID CARD (With Photo & Position)
                    // ══════════════════════════════════════════════════════════
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Candidate Photo Box
                        Container(
                          width: 76,
                          height: 88,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: primaryBadgeColor.withValues(alpha: 0.5),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: (photoUrl != null && photoUrl!.isNotEmpty)
                              ? Image.network(
                                  photoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stack) => Icon(
                                    Icons.person_rounded,
                                    size: 40,
                                    color: isDark ? Colors.white38 : Colors.grey.shade400,
                                  ),
                                )
                              : Icon(
                                  Icons.person_rounded,
                                  size: 40,
                                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                                ),
                        ),
                        const SizedBox(width: 14),

                        // Candidate Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (positionTitle != null) ...[
                                Text(
                                  'पद (Position): $positionTitle',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: primaryBadgeColor,
                                  ),
                                ),
                                const SizedBox(height: 2),
                              ],
                              Text(
                                'उम्मेदवार कोड: $idNumber',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                ),
                              ),
                              if (councilNumber != null && councilNumber!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Council/Reg: $councilNumber',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                              if (phone != null && phone!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'सम्पर्क: $phone',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white60 : Colors.grey.shade700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.verified_rounded, size: 13, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Certified Candidate',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10B981),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Bottom Seal & Auth Signature Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 14, color: primaryBadgeColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Official Digital Credential • निर्वाचन व्यवस्थापन प्रणाली',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white38 : Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: Colors.grey.shade400)),
                            ),
                            child: const Text(
                              'Election Officer (अधिकृत)',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBadgeColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.print_rounded, size: 18),
                    label: const Text('Print / Download PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () => _openPrintUrl(context),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}
