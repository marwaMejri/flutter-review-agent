import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/sync/sync_service.dart';

/// Shows a message each time the notes are synced.
class SyncBanner extends StatefulWidget {
  const SyncBanner({required this.child, super.key});

  final Widget child;

  @override
  State<SyncBanner> createState() => _SyncBannerState();
}

class _SyncBannerState extends State<SyncBanner> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncService.onSynced(
      () => ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Notes synced'))),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
