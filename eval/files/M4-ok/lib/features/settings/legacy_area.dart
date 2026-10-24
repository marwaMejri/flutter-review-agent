import 'package:material_ui/material_ui.dart';

/// Wraps a widget from a package that still uses the SDK Material.
class LegacyArea extends StatelessWidget {
  const LegacyArea({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Needed by dropdown_button2 3.1.0, which still uses the SDK Material.
    // Remove when a migrated version is published.
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(child: child);
  }
}
