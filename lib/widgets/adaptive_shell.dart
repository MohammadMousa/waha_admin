import 'package:flutter/material.dart';

import 'admin_sidebar.dart';

/// Below this width the admin uses its phone layout.
const double kNarrowWidth = 700;

/// Wraps a signed-in screen. On wide screens it returns the screen untouched
/// (the screen draws its own pinned sidebar). On narrow screens the sidebar is
/// hidden from the screen and shown in a slide-out panel opened from a top bar.
class AdaptiveShell extends StatelessWidget {
  final String currentRoute;
  final Widget child;
  const AdaptiveShell({super.key, required this.currentRoute, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= kNarrowWidth) return child;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 48,
        titleSpacing: 0,
        leading: Builder(
          builder: (c) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(c).openDrawer(),
          ),
        ),
        title: const Text('Waha Admin', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      drawer: Drawer(
        width: 290,
        elevation: 24,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        shape: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: SafeArea(
          child: AdminSidebar(currentRoute: currentRoute, inDrawer: true),
        ),
      ),
      body: child,
    );
  }
}

/// Outer side padding of a page: tighter on phones.
double pagePad(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kNarrowWidth ? 12 : 24;

/// A row on wide screens; on phones the same children wrap onto several lines
/// (spacers and fixed gaps are dropped, the wrap supplies the spacing).
Widget adaptiveRow(BuildContext context, {required List<Widget> children}) {
  if (MediaQuery.sizeOf(context).width >= kNarrowWidth) return Row(children: children);
  return Wrap(
    alignment: WrapAlignment.start,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final w in children)
        if (w is! Spacer && !(w is SizedBox && w.child == null)) w,
    ],
  );
}
