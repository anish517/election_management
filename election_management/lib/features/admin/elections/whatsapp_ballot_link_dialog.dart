import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_helper.dart';

/// During voting, an org admin or election officer sends a voter their
/// single-use ballot link through WhatsApp (click-to-chat with the message
/// filled in; the staff member presses send in WhatsApp).
class WhatsAppBallotLinkDialog extends StatelessWidget {
  static const whatsAppGreen = Color(0xFF25D366);

  final String voterName;
  final Map<String, dynamic> link;

  const WhatsAppBallotLinkDialog({super.key, required this.voterName, required this.link});

  /// Creates (or reuses) the voter's ballot link, then shows this dialog.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref,
    String electionId,
    Map<String, dynamic> voter,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref
          .read(apiClientProvider)
          .post(ApiConstants.voterBallotLink(electionId, voter['id'].toString()));
      if (!context.mounted) return;
      final name = (voter['full_name'] as String?)?.trim() ??
          '${voter['first_name'] ?? ''} ${voter['last_name'] ?? ''}'.trim();
      await showDialog(
        context: context,
        builder: (_) => WhatsAppBallotLinkDialog(voterName: name, link: res.data as Map<String, dynamic>),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(extractApiErrorMessage(e, fallback: 'Could not create the ballot link.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final expires = DateTime.tryParse(link['expires_at'] as String? ?? '');
    final message = link['message'] as String? ?? '';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.chat_rounded, color: whatsAppGreen),
          SizedBox(width: 10),
          Expanded(child: Text('Send ballot link on WhatsApp')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To: $voterName  (+${link['phone']})', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceVariant : const Color(0xFFDCF8C6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(message, style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
            const SizedBox(height: 10),
            Text(
              [
                'Works once',
                if (expires != null) 'valid until ${DateFormat('d MMM, h:mm a').format(expires.toLocal())}',
              ].join(', '),
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link['direct_link_url'] as String? ?? ''));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ballot link copied')));
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy link'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: whatsAppGreen, foregroundColor: Colors.white),
          onPressed: () {
            launchUrl(Uri.parse(link['whatsapp_url'] as String), webOnlyWindowName: '_blank');
            Navigator.pop(context);
          },
          icon: const Icon(Icons.send_rounded, size: 16),
          label: const Text('Open WhatsApp'),
        ),
      ],
    );
  }
}
