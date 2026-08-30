import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/glass_card.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });

    final error = await ref.read(authProvider.notifier).requestPasswordReset(
      _emailCtrl.text.trim(),
    );

    if (mounted) {
      setState(() { _isLoading = false; _errorMessage = error; });
      if (error == null) {
        context.pushNamed(
          'reset-password',
          pathParameters: {'email': Uri.encodeComponent(_emailCtrl.text.trim())},
        );
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
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios_rounded, size: 16,
                              color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode),
                            const SizedBox(width: 4),
                            Text('Back to Login',
                              style: TextStyle(fontSize: 13,
                                color: isDark ? AppColors.textMuted : AppColors.textSecondaryLightMode)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryLight]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 24),
                      Text('Forgot Password',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 26)),
                      const SizedBox(height: 8),
                      Text('Enter your admin email and we\'ll send you a 6-digit reset code.',
                        style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.primaryLight, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Password reset is only available for Organization Admins and Election Officers. '
                                'Voters and members can sign in using OTP / Phone.',
                                style: TextStyle(fontSize: 12.5,
                                  color: isDark ? Colors.white70 : AppColors.primary, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
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
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Admin Email Address',
                          prefixIcon: Icon(Icons.email_outlined),
                          hintText: 'e.g. admin@yourorganization.com',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Email is required';
                          if (!v.contains('@')) return 'Enter a valid email address';
                          return null;
                        },
                        onFieldSubmitted: (_) => _sendResetCode(),
                      ),
                      const SizedBox(height: 28),
                      LoadingButton(
                        onPressed: _sendResetCode,
                        isLoading: _isLoading,
                        label: 'Send Reset Code',
                        icon: Icons.send_rounded,
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
