import 'dart:async';

import 'package:material_ui/material_ui.dart';

/// Shows the current time, updated every minute.
class ClockBadge extends StatefulWidget {
  const ClockBadge({super.key});

  @override
  State<ClockBadge> createState() => _ClockBadgeState();
}

class _ClockBadgeState extends State<ClockBadge> {
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(minutes: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text('${_now.hour}:${_now.minute.toString().padLeft(2, '0')}');
  }
}
