import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Shows how long ago the list was checked, updated every second.
class LastChecked extends StatefulWidget {
  const LastChecked({super.key});

  @override
  State<LastChecked> createState() => _LastCheckedState();
}

class _LastCheckedState extends State<LastChecked> {
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Checked $_secondsSinceCheck s ago'),
    );
  }
}
