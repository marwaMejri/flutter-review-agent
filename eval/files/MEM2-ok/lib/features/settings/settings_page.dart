import 'package:dropdown_button2/dropdown_button2.dart';
// Needed by dropdown_button2 3.1.0, which still uses the SDK Material
// (see MaterialUiCompatibilityBridge in lib/app/app.dart).
// Remove when a migrated version is published.
// ignore: migrate_design_widgets
import 'package:flutter/material.dart'
    as legacy
    show InputDecoration, Material, MaterialType, OutlineInputBorder;
import 'package:material_ui/material_ui.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final ValueNotifier<String?> _channel = ValueNotifier<String?>('stable');

  @override
  void dispose() {
    _channel.dispose();
    super.dispose();
  }

  void _showSaved(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Channel saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: legacy.Material(
          type: legacy.MaterialType.transparency,
          child: DropdownButtonFormField2<String>(
            valueListenable: _channel,
            decoration: const legacy.InputDecoration(
              labelText: 'Update channel',
              border: legacy.OutlineInputBorder(),
            ),
            items: const <DropdownItem<String>>[
              DropdownItem<String>(value: 'stable', child: Text('Stable')),
              DropdownItem<String>(value: 'beta', child: Text('Beta')),
            ],
            onChanged: (String? value) {
              _channel.value = value;
              _showSaved(context);
            },
          ),
        ),
      ),
    );
  }
}
