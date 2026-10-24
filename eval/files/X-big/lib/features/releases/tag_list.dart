import 'package:material_ui/material_ui.dart';

/// Lists the tags of a note.
class TagList extends StatelessWidget {
  const TagList({required this.tags, super.key});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: tags.map((String tag) => ListTile(title: Text(tag))).toList(),
    );
  }
}
