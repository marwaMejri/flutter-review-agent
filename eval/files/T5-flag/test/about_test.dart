import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';
import 'package:material_ui_packages_migration/features/about/about_page.dart';

void main() {
  testWidgets('the About button opens the About page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });
}
