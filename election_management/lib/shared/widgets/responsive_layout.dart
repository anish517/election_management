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

/// Lays a page's scroll view across the full available width, so its
/// scrollbar sits at the window edge and the wheel scrolls from anywhere,
/// while keeping the content centred within [maxWidth].
///
/// [builder] gets `pad`, which widens a padding by the side gutters; pass the
/// scroll view's padding through it.
class CenteredScroll extends StatelessWidget {
  final double maxWidth;
  final Widget Function(
      BuildContext context, EdgeInsets Function(EdgeInsets) pad) builder;

  const CenteredScroll({
    super.key,
    required this.maxWidth,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth > maxWidth
            ? (constraints.maxWidth - maxWidth) / 2
            : 0.0;
        return builder(
          context,
          (base) => base + EdgeInsets.symmetric(horizontal: gutter),
        );
      },
    );
  }
}
