import 'package:material_ui/material_ui.dart';

/// A field to search the release notes. The parent owns the controller.
class NoteSearch extends StatelessWidget {
  const NoteSearch({
    required this.controller,
    required this.onSearch,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: const InputDecoration(labelText: 'Search'),
      onSubmitted: onSearch,
    );
  }
}
