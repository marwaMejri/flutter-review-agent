import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

/// Shows how many releases the user has not opened yet.
class UnreadHeader extends StatelessWidget {
  const UnreadHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: countUnread(),
      builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
        return ListTile(title: Text('${snapshot.data ?? 0} new releases'));
      },
    );
  }
}
