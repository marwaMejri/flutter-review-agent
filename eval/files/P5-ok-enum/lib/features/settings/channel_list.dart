import 'package:material_ui/material_ui.dart';

/// The update channels of the app.
enum Channel { stable, beta }

/// Shows every update channel.
class ChannelList extends StatelessWidget {
  const ChannelList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (final Channel channel in Channel.values) Text(channel.name),
      ],
    );
  }
}
