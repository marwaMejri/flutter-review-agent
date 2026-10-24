import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('a release that fixes a bug shows a Fix badge', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    expect(find.text('Fix'), findsOneWidget);
  });
}
