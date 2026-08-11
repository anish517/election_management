import 'package:flutter/material.dart';
class ResponsiveLayout {
  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < 850;
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= 850;
}

/// Wraps page content (like Dashboards, Lists) to a maximum width
/// of 1000 pixels so it doesn't stretch awkwardly on desktop.
class ResponsivePageWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsivePageWrapper({
    super.key,
    required this.child,
    this.maxWidth = 1000,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Wraps forms (Login, Register, Create Election) to a maximum width
/// of 450 pixels so they look like elegant desktop dialogs.
class ResponsiveFormWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveFormWrapper({
    super.key,
    required this.child,
    this.maxWidth = 450,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
