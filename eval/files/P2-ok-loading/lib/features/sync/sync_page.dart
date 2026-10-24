import 'package:material_ui/material_ui.dart';

/// Syncs the notes, and shows a spinner while the sync runs.
class SyncPage extends StatefulWidget {
  const SyncPage({required this.sync, super.key});

  final Future<void> Function() sync;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  bool _loading = false;

  Future<void> _run() async {
    setState(() => _loading = true);
    await widget.sync();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: FilledButton(
                onPressed: _run,
                child: const Text('Sync now'),
              ),
            ),
    );
  }
}
