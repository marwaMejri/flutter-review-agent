import 'package:material_ui/material_ui.dart';

/// A field to search the release notes.
class NoteSearch extends StatefulWidget {
  const NoteSearch({required this.onSearch, super.key});

  final ValueChanged<String> onSearch;

  @override
  State<NoteSearch> createState() => _NoteSearchState();
}

class _NoteSearchState extends State<NoteSearch> {
  final TextEditingController _controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(labelText: 'Search'),
      onSubmitted: widget.onSearch,
    );
  }
}
