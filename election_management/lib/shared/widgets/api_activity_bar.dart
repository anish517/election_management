import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';

/// Thin progress bar along the top of every page while an API request is
/// taking a while (shown after a short delay so quick requests don't flicker).
class ApiActivityBar extends StatefulWidget {
  const ApiActivityBar({super.key});

  @override
  State<ApiActivityBar> createState() => _ApiActivityBarState();
}

class _ApiActivityBarState extends State<ApiActivityBar> {
  static const _delay = Duration(milliseconds: 300);
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    apiActivity.addListener(_onActivity);
    _onActivity();
  }

  void _onActivity() {
    if (apiActivity.value > 0) {
      _timer ??= Timer(_delay, () {
        if (mounted && apiActivity.value > 0) setState(() => _visible = true);
      });
    } else {
      _timer?.cancel();
      _timer = null;
      if (_visible && mounted) setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    apiActivity.removeListener(_onActivity);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const IgnorePointer(
      child: SizedBox(
        height: 3,
        child: LinearProgressIndicator(
          minHeight: 3,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation(AppColors.primaryLight),
        ),
      ),
    );
  }
}
