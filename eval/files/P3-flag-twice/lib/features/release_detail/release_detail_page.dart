import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui_packages_migration/core/data/releases.dart';

class ReleaseDetailPage extends StatelessWidget {
  const ReleaseDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final Release? release = releaseById(id);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          release == null ? 'Not found' : 'Version ${release.version}',
        ),
        actions: <Widget>[
          if (release != null) _buildTag(context, release.date),
          if (release != null) _buildTag(context, release.summary),
        ],
      ),
      body: release == null
          ? const Center(child: Text('This release does not exist.'))
          : Markdown(
              data: release.notes,
              styleSheet: MarkdownStyleSheet(
                code: TextStyle(
                  backgroundColor: Theme.of(context).cardTheme.color,
                ),
                codeblockDecoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
    );
  }

  Widget _buildTag(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Chip(label: Text(label)),
    );
  }
}
