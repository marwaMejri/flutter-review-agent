import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('an open release shows that it is synced', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Version 3.0.0'));
    await tester.pumpAndSettle();

    expect(find.text('3.0.0 synced'), findsOneWidget);
  });
}
