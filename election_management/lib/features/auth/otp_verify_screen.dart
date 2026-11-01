import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/responsive_layout.dart';

class OtpVerifyScreen extends ConsumerStatefulWidget {
  final String identifier;
  const OtpVerifyScreen({super.key, required this.identifier});

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());
  final _lastDigits = List.filled(6, '');
  bool _isLoading = false;
  String? _errorMessage;

  String get _fullOtp => _controllers.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_fullOtp.length < 6) {
      setState(() => _errorMessage = 'Please enter the complete 6-digit code.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    final error = await ref.read(authProvider.notifier).loginWithOtp(
      phoneOrEmail: widget.identifier,
      otp: _fullOtp,
    );
    if (mounted) {
      setState(() { _isLoading = false; _errorMessage = error; });
    }
  }

  void _onDigitInput(int index, String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      _setDigit(index, '');
      if (index > 0) _focusNodes[index - 1].requestFocus();
      return;
    }

    final previous = _lastDigits[index];
    final typedOver = digits.length == 2 && previous.isNotEmpty && digits.contains(previous);
    if (digits.length == 1 || typedOver) {
      // One new digit (possibly typed over the box's old one, on either side of it).
      final digit = digits.length == 1 ? digits : (digits[0] == previous ? digits[1] : digits[0]);
      _setDigit(index, digit);
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      }
    } else {
      // Paste or SMS autofill: spread the code across the boxes from here on.
      // A full 6-digit code always fills from the first box.
      var pasted = digits;
      if (previous.isNotEmpty) {
        // The box's old digit is still in the text, before or after the paste
        // depending on where the cursor was; the caret sits after the insert.
        final caret = _controllers[index].selection.baseOffset;
        final insertedAtEnd = caret < 0 || caret >= value.length;
        pasted = insertedAtEnd ? pasted.substring(1) : pasted.substring(0, pasted.length - 1);
      }
      final start = pasted.length >= 6 ? 0 : index;
      final chars = pasted.characters.take(6 - start).toList();
      for (var k = 0; k < chars.length; k++) {
        _setDigit(start + k, chars[k]);
      }
      final next = start + chars.length;
      if (next <= 5) {
        _focusNodes[next].requestFocus();
      } else {
        _focusNodes[5].unfocus();
      }
    }

    if (_fullOtp.length == 6 && !_isLoading) _verify();
  }

  void _setDigit(int index, String digit) {
    _lastDigits[index] = digit;
    _controllers[index].value = TextEditingValue(
      text: digit,
      selection: TextSelection.collapsed(offset: digit.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_ios_rounded),
        ),
      ),
      body: SafeArea(
        child: CenteredScroll(
          maxWidth: 480,
          builder: (context, pad) => SingleChildScrollView(
            padding: pad(const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                const Icon(Icons.verified_user_outlined, size: 48, color: AppColors.primaryLight),
                const SizedBox(height: 20),
                Text('Verify Your Identity', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Enter the 6-digit code sent to\n${widget.identifier}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 36),
                _buildOtpFields(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                LoadingButton(
                  onPressed: _verify,
                  isLoading: _isLoading,
                  label: 'Verify Code',
                  icon: Icons.check_circle_outline_rounded,
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await ref.read(authProvider.notifier).requestOtp(widget.identifier);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('New OTP sent!')),
                        );
                      }
                    },
                    child: const Text('Resend Code'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOtpFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        const gap = 6.0;
        final totalGaps = gap * 5;
        final boxWidth = ((availableWidth - totalGaps) / 6).clamp(38.0, 48.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 5 ? gap : 0),
              child: SizedBox(
                width: boxWidth,
                height: 54,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  // No maxLength: it cut a pasted code down to its first digit.
                  // _onDigitInput spreads multi-digit input across the boxes.
                  autofillHints: i == 0 ? const [AutofillHints.oneTimeCode] : null,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.surfaceVariant
                        : Colors.black.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
                    ),
                  ),
                  onChanged: (v) => _onDigitInput(i, v),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
