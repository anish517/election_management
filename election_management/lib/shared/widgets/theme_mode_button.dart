import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/theme_provider.dart';

/// App-bar menu to pick System / Light / Dark appearance (persisted).
class ThemeModeButton extends ConsumerWidget {
  const ThemeModeButton({super.key});

  static const _options = [
    (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    (ThemeMode.light, 'Light', Icons.light_mode_rounded),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final current = _options.firstWhere((o) => o.$1 == mode);

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: Icon(current.$3, size: 20),
      initialValue: mode,
      onSelected: (m) => ref.read(themeModeProvider.notifier).setTheme(m),
      itemBuilder: (context) => [
        for (final (value, label, icon) in _options)
          CheckedPopupMenuItem(
            value: value,
            checked: value == mode,
            child: Row(
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 10),
                Text(label),
              ],
            ),
          ),
      ],
    );
  }
}
