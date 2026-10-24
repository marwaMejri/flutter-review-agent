import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('the changelog lists the release notes', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Changelog'));
    await tester.pumpAndSettle();

    expect(find.text('Changelog'), findsOneWidget);
    expect(find.text('## Background sync'), findsOneWidget);
  });
}
