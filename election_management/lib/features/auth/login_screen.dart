import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/theme_mode_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailPasswordKey = GlobalKey<FormState>();
  final _otpKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _otpIdentCtrl = TextEditingController();

  bool _passwordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _otpIdentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithPassword() async {
    if (!_emailPasswordKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    final error = await ref.read(authProvider.notifier).login(
      emailOrPhone: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
    );
    if (mounted) setState(() { _isLoading = false; _errorMessage = error; });
  }

  Future<void> _requestOtp() async {
    if (!_otpKey.currentState!.validate()) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    final error = await ref.read(authProvider.notifier).requestOtp(
      _otpIdentCtrl.text.trim(),
    );
    if (mounted) {
      setState(() => _isLoading = false);
      if (error == null) {
        context.pushNamed('otp', pathParameters: {'identifier': _otpIdentCtrl.text.trim()});
      } else {
        setState(() => _errorMessage = error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actions: const [ThemeModeButton(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: Center(
          child: ResponsiveFormWrapper(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: GlassCard(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 40),
                    _buildTabBar(),
                    const SizedBox(height: 28),
                    if (_errorMessage != null) _buildError(),
                    _buildTabContent(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.how_to_vote_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Election Nepal',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Sign in to your election account',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        // Slate-300 on the slate-700 tab track; textMuted was too faint in dark mode.
        unselectedLabelColor: isDark ? const Color(0xFFCBD5E1) : AppColors.textSecondaryLightMode,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        tabs: const [
          Tab(text: 'Password'),
          Tab(text: 'OTP Login'),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_errorMessage!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // Sized to the active tab so the card has no dead space below the form.
  Widget _buildTabContent() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _tabController.index == 0 ? _buildPasswordTab() : _buildOtpTab(),
    );
  }

  Widget _buildPasswordTab() {
    return Form(
      key: _emailPasswordKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email or Phone',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: !_passwordVisible,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                  icon: Icon(_passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              onFieldSubmitted: (_) => _loginWithPassword(),
            ),
            // Forgot Password link
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.pushNamed('forgot-password'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot Password?', style: TextStyle(fontSize: 13)),
              ),
            ),
            const SizedBox(height: 12),
            LoadingButton(
              onPressed: _loginWithPassword,
              isLoading: _isLoading,
              label: 'Sign In',
              icon: Icons.login_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpTab() {
    return Form(
      key: _otpKey,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your phone number or email and we\'ll send you a one-time code.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _otpIdentCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Phone or Email',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              validator: (v) => v == null || v.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 24),
            LoadingButton(
              onPressed: _requestOtp,
              isLoading: _isLoading,
              label: 'Send OTP',
              icon: Icons.send_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
