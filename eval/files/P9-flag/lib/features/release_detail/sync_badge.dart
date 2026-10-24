import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Turns a sync icon once when a release opens.
class SyncBadge extends StatefulWidget {
  const SyncBadge({required this.version, super.key});

  final String version;

  @override
  State<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<SyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Transform.rotate(
              angle: _controller.value * 2 * math.pi,
              child: const Icon(Icons.sync),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${widget.version} synced'),
            ),
          ],
        );
      },
    );
  }
}
