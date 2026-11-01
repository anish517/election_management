import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/network/api_constants.dart';

/// The organization prefix. It is also the organization's public web address
/// (`electionnepal.org/<prefix>`), shown under the field as you type.
class OrgPrefixField extends StatelessWidget {
  final TextEditingController controller;
  final InputDecoration decoration;

  const OrgPrefixField({super.key, required this.controller, required this.decoration});

  static final _allowed = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$');

  static String? validate(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (!_allowed.hasMatch(v)) return 'Letters, numbers and hyphens only';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final prefix = value.text.trim();
        final address = ApiConstants.orgPublicUrl(prefix.isEmpty ? '<prefix>' : prefix)
            .replaceFirst(RegExp(r'^https?://'), '');
        return TextFormField(
          controller: controller,
          decoration: decoration.copyWith(helperText: address, helperMaxLines: 2),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
          maxLength: 30,
          buildCounter: (_, {required currentLength, required isFocused, required maxLength}) => null,
          validator: validate,
        );
      },
    );
  }
}
