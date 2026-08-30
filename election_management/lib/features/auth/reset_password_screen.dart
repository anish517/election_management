import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/glass_card.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _newPasswordVisible = false;
  bool _confirmPasswordVisible = false;
  String? _errorMessage;

  late final String _decodedEmail;

  @override
  void initState() {
    super.initState();
    _decodedEmail = Uri.decodeComponent(widget.email);
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    final error = await ref.read(authProvider.notifier).confirmPasswordReset(
      email: _decodedEmail,
      otp: _otpCtrl.text.trim(),
      newPassword: _newPasswordCtrl.text,
      confirmPassword: _confirmPasswordCtrl.text,
    );

    if (mounted) {
      setState(() { _isLoading = false; _errorMessage = error; });
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('Password reset successfully! Please sign in.'),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        context.go('/login');
      }
    }
  }

  Future<void> _resendCode() async {
    setState(() { _errorMessage = null; });
    final error = await ref.read(authProvider.notifier).requestPasswordReset(_decodedEmail);
    if (mounted) {
      if (error == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('A new reset code has been sent to your email.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        setState(() => _errorMessage = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ResponsiveFormWrapper(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: GlassCard(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_rounded, size: 16,
                              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode),
                            const SizedBox(width: 4),
                            Text('Back',
                              style: TextStyle(fontSize: 13,
                                color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Icon & Title
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.green.shade700, Colors.green.shade500],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 24),
                      Text('Reset Password',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.bodyMedium,
                          children: [
                            const TextSpan(text: 'Enter the 6-digit code sent to '),
                            TextSpan(
                              text: _decodedEmail,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const TextSpan(text: ' and set your new password.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Error
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_errorMessage!,
                                style: const TextStyle(color: AppColors.error, fontSize: 13))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // OTP Field
                      TextFormField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 8),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          labelText: 'Reset Code (6 digits)',
                          prefixIcon: Icon(Icons.pin_rounded),
                          counterText: '',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Reset code is required';
                          if (v.length != 6) return 'Enter the 6-digit code';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // New Password
                      TextFormField(
                        controller: _newPasswordCtrl,
                        obscureText: !_newPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _newPasswordVisible = !_newPasswordVisible),
                            icon: Icon(_newPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'New password is required';
                          if (v.length < 8) return 'Password must be at least 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Confirm Password
                      TextFormField(
                        controller: _confirmPasswordCtrl,
                        obscureText: !_confirmPasswordVisible,
                        decoration: InputDecoration(
                          labelText: 'Confirm New Password',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                            icon: Icon(_confirmPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please confirm your password';
                          if (v != _newPasswordCtrl.text) return 'Passwords do not match';
                          return null;
                        },
                        onFieldSubmitted: (_) => _resetPassword(),
                      ),
                      const SizedBox(height: 28),

                      // Submit Button
                      LoadingButton(
                        onPressed: _resetPassword,
                        isLoading: _isLoading,
                        label: 'Reset Password',
                        icon: Icons.check_rounded,
                      ),
                      const SizedBox(height: 16),

                      // Resend Code
                      Center(
                        child: TextButton.icon(
                          onPressed: _resendCode,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Resend Code'),
                          style: TextButton.styleFrom(
                            foregroundColor: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
