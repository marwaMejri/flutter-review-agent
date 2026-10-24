import 'package:material_ui/material_ui.dart';

/// A field to search the release notes.
class NoteSearch extends StatelessWidget {
  const NoteSearch({required this.onSearch, super.key});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return TextField(
      controller: controller,
      decoration: const InputDecoration(labelText: 'Search'),
      onSubmitted: onSearch,
    );
  }
}
