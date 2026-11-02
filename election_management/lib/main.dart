import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'shared/widgets/api_activity_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait on mobile, allow landscape on tablet/web
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style for dark theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ProviderScope(child: ElectionManagementApp()));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class ElectionManagementApp extends ConsumerWidget {
  const ElectionManagementApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'EMS - Election Management System in Nepal',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: const AppScrollBehavior(),
      routerConfig: router,
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.globalBackgroundGradient
                : AppColors.globalBackgroundGradientLight,
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    // The footer owns the bottom safe-area inset.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                  const PoweredByFooter(),
                ],
              ),
              const Positioned(top: 0, left: 0, right: 0, child: ApiActivityBar()),
            ],
          ),
        );
      },
    );
  }
}

/// App-wide "Powered by: Omway Technologies" strip shown under every screen;
/// the name links to the Omway website.
class PoweredByFooter extends StatelessWidget {
  const PoweredByFooter({super.key});

  static final _omwayUrl = Uri.parse('https://omwaytechnologies.com');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = TextStyle(
      fontSize: 11.5,
      letterSpacing: 0.2,
      color: isDark ? AppColors.textSecondary : AppColors.textMuted,
    );
    return Material(
      color: isDark ? const Color(0xFF0B0F19) : Colors.white,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Powered by: ', style: baseStyle),
              // Not focusable: a focus node out here, beside the router's
              // Navigator, trips Flutter's startup focus traversal.
              InkWell(
                canRequestFocus: false,
                onTap: () => launchUrl(_omwayUrl, webOnlyWindowName: '_blank'),
                borderRadius: BorderRadius.circular(4),
                child: Text(
                  'Omway Technologies',
                  style: baseStyle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.primaryLight : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
