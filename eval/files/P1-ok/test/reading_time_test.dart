import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('each release shows its reading time', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('1 min read'), findsNWidgets(3));
  });
}
