import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('the list shows when it was last checked', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pump();
    expect(find.text('Checked 0 s ago'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Checked 1 s ago'), findsOneWidget);
  });
}
