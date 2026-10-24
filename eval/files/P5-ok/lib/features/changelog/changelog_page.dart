import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Changelog')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: changelogLines.length,
        itemBuilder: (BuildContext context, int index) =>
            Text(changelogLines[index]),
      ),
    );
  }
}
