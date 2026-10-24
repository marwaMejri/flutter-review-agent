import 'package:material_ui/material_ui.dart';

/// Says what the app is and who makes it.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: const Center(child: Text('$appName, by the Notely team.')),
    );
  }
}
