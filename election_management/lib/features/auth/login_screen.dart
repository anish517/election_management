import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/tenant_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/loading_button.dart';
import '../../shared/widgets/org_logo.dart';
import '../../shared/widgets/responsive_layout.dart';
import '../../shared/widgets/glass_card.dart';
import '../../shared/widgets/theme_mode_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final String? orgPrefix;
  final String? portalToken;
  const LoginScreen({super.key, this.orgPrefix, this.portalToken});

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
      portalToken: widget.portalToken,
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
    final hasOrg = widget.orgPrefix != null && widget.orgPrefix!.trim().isNotEmpty;
    final orgHandle = hasOrg
        ? (widget.portalToken != null && widget.portalToken!.isNotEmpty
            ? '${widget.portalToken}/${widget.orgPrefix!.trim()}'
            : widget.orgPrefix!.trim())
        : '';
    final orgAsync = hasOrg ? ref.watch(publicOrganizationProvider(orgHandle)) : null;
    final org = orgAsync?.valueOrNull;
    final brandColor = parseBrandColor(org?.brandColor) ?? AppColors.primary;

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
                child: (orgAsync != null &&
                        orgAsync.hasError &&
                        widget.portalToken != null &&
                        widget.portalToken!.isNotEmpty)
                    ? _buildTokenBlockedContent()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(orgAsync: orgAsync, org: org, brandColor: brandColor),
                          const SizedBox(height: 36),
                          _buildTabBar(brandColor: brandColor),
                          const SizedBox(height: 28),
                          if (_errorMessage != null) _buildError(),
                          _buildTabContent(brandColor: brandColor),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTokenBlockedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Access Denied: Invalid Security Token',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The security token in this web address is incorrect or has been altered. Sign-in to this private organization portal is completely blocked.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Security Notice',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '• Please make sure you did not remove or modify any letters in the URL.\n• Contact your organization administrator to obtain the official private portal link.\n• Unauthorized access attempts are monitored and recorded.',
          style: TextStyle(
            fontSize: 12.5,
            color: Theme.of(context).textTheme.bodySmall?.color,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 18, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                'Sign-in locked. Valid private portal link required.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({
    AsyncValue<PublicOrganization>? orgAsync,
    PublicOrganization? org,
    required Color brandColor,
  }) {
    if (orgAsync != null && orgAsync.isLoading) {
      return Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loading portal...',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text('Connecting to organization', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
    }

    if (orgAsync != null && orgAsync.hasError && widget.portalToken != null && widget.portalToken!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Invalid or Expired Portal Link',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The security token in this URL is incorrect. Access to this private election portal is restricted. Please use the exact link provided by your organization.',
                    style: TextStyle(fontSize: 12.5, color: Theme.of(context).textTheme.bodySmall?.color, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (org != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OrgLogo(name: org.name, logoUrl: org.logoUrl, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.name,
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (org.orgType.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        org.orgType.replaceAll('_', ' ').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: brandColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Sign in to ${org.name} Election Portal',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      );
    }

    // Default generic platform branding
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
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

  Widget _buildTabBar({required Color brandColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceVariant : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: brandColor,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
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

  Widget _buildTabContent({required Color brandColor}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _tabController.index == 0
          ? _buildPasswordTab(brandColor: brandColor)
          : _buildOtpTab(brandColor: brandColor),
    );
  }

  Widget _buildPasswordTab({required Color brandColor}) {
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.pushNamed('forgot-password'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primaryLight
                      : brandColor,
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
              backgroundColor: brandColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpTab({required Color brandColor}) {
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
              backgroundColor: brandColor,
            ),
          ],
        ),
      ),
    );
  }
}
