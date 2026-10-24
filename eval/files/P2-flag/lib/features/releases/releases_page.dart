import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

class ReleasesPage extends StatefulWidget {
  const ReleasesPage({super.key});

  @override
  State<ReleasesPage> createState() => _ReleasesPageState();
}

class _ReleasesPageState extends State<ReleasesPage> {
  int _secondsSinceCheck = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _secondsSinceCheck++;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Checked $_secondsSinceCheck s ago'),
          ),
          for (final Release release in releases)
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
