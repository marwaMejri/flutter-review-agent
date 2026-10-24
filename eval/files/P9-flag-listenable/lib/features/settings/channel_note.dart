import 'package:material_ui/material_ui.dart';

/// Shows the chosen update channel, and a note about restarts.
class ChannelNote extends StatelessWidget {
  const ChannelNote({required this.channel, super.key});

  final ValueListenable<String?> channel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: channel,
      builder: (BuildContext context, String? value, Widget? child) {
        return Column(
          children: <Widget>[
            Text('Channel: ${value ?? 'none'}'),
            Text(
              'Changes apply after a restart.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
