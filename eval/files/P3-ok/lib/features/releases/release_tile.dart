import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

class ReleaseTile extends StatelessWidget {
  const ReleaseTile({required this.release, super.key});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        child: const Icon(Icons.new_releases),
      ),
      title: Text('Version ${release.version}'),
      subtitle: Text('${release.date} · ${release.summary}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.go('/releases/${release.id}'),
    );
  }
}
