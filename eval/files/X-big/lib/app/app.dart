import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/app/router.dart';
import 'package:material_ui_packages_migration/core/theme/app_theme.dart';

/// The root of the app: theme, router and the compatibility bridge.
class ReleaseNotesApp extends StatefulWidget {
  const ReleaseNotesApp({super.key});

  @override
  State<ReleaseNotesApp> createState() => _ReleaseNotesAppState();
}

class _ReleaseNotesAppState extends State<ReleaseNotesApp> {
  final GoRouter _router = createRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Release notes',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: _router,
      builder: (BuildContext context, Widget? child) {
        // Needed by dropdown_button2 3.1.0, which still uses the SDK Material.
        // Remove when a migrated version is published.
        // ignore: deprecated_member_use
        return MaterialUiCompatibilityBridge(child: child!);
      },
    );
  }
}
