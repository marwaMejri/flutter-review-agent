import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('the list shows every release', (WidgetTester tester) async {
    tester.pumpWidget(const ReleaseNotesApp());

    expect(find.text('Version 3.0.0'), findsOneWidget);
  });
}
