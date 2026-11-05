import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_constants.dart';

/// The organization prefix. It is also the organization's public web address
/// (`electionnepal.org/#/o/<prefix>`), shown under the field as you type.
class OrgPrefixField extends StatelessWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool readOnly;
  final String? portalToken;

  const OrgPrefixField({
    super.key,
    required this.controller,
    required this.decoration,
    this.readOnly = false,
    this.portalToken,
  });

  static final _allowed = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$');

  static String? validate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!_allowed.hasMatch(v)) return 'Letters, numbers and hyphens only';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final prefix = value.text.trim();
        final address = ApiConstants.orgPublicUrl(prefix.isEmpty ? '<prefix>' : prefix)
            .replaceFirst(RegExp(r'^https?://'), '');

        return TextFormField(
          controller: controller,
          readOnly: readOnly,
          decoration: decoration.copyWith(
            filled: readOnly ? true : decoration.filled,
            fillColor: readOnly
                ? (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100)
                : decoration.fillColor,
            helperText: readOnly
                ? 'Web address is locked. Contact Platform Admin to change.'
                : address,
            helperMaxLines: 2,
            prefixIcon: readOnly
                ? const Icon(Icons.lock_outline_rounded, size: 18)
                : decoration.prefixIcon,
            suffixIcon: readOnly && prefix.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy Login Link',
                    onPressed: () {
                      final url = ApiConstants.orgLoginUrl(prefix, portalToken: portalToken);
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied Login Link ($url) to clipboard'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  )
                : decoration.suffixIcon,
          ),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: readOnly ? [] : [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
          maxLength: 30,
          buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
          validator: readOnly ? null : validate,
        );
      },
    );
  }
}
