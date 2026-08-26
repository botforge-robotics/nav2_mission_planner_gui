import 'package:flutter/widgets.dart';

/// Mobile/tablet/desktop breakpoints, used to switch between the reference
/// mockup's phone-card layout and a wider adaptive layout — not to just
/// scale the same layout up.
enum DeviceClass { mobile, tablet, desktop }

class Breakpoints {
  Breakpoints._();

  static const double tablet = 600;
  static const double desktop = 1024;

  static DeviceClass of(BuildContext context) =>
      classify(MediaQuery.sizeOf(context).width);

  static DeviceClass classify(double width) {
    if (width >= desktop) return DeviceClass.desktop;
    if (width >= tablet) return DeviceClass.tablet;
    return DeviceClass.mobile;
  }
}

/// Picks between mobile/tablet/desktop builders for the current width.
/// `tablet`/`desktop` fall back to the next-narrower builder when omitted,
/// so a screen only has to define the breakpoints where its layout actually
/// changes.
class Responsive extends StatelessWidget {
  const Responsive(
      {super.key, required this.mobile, this.tablet, this.desktop});

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    switch (Breakpoints.of(context)) {
      case DeviceClass.desktop:
        return (desktop ?? tablet ?? mobile)(context);
      case DeviceClass.tablet:
        return (tablet ?? mobile)(context);
      case DeviceClass.mobile:
        return mobile(context);
    }
  }
}

/// Centers content in a fixed-width column on tablet/desktop instead of
/// letting a mobile-first layout stretch edge-to-edge — the reference's own
/// screens are all phone-card width even in the flow diagram, and that
/// proportion reads better centered than stretched on a wide window.
class CenteredFormColumn extends StatelessWidget {
  const CenteredFormColumn(
      {super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isMobile = Breakpoints.of(context) == DeviceClass.mobile;
    if (isMobile) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
