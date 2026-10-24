import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

class ReleasesPage extends StatelessWidget {
  const ReleasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<Release> sorted = List<Release>.of(releases)
      ..sort((Release a, Release b) => a.date.compareTo(b.date));
    return Scaffold(
      appBar: AppBar(
        title: const Text('$appName releases'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          for (final Release release in sorted)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                child: const Icon(Icons.new_releases),
              ),
              title: Text('Version ${release.version}'),
              subtitle: Text('${release.date} · ${release.summary}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/releases/${release.id}'),
            ),
        ],
      ),
    );
  }
}
