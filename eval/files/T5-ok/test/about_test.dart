import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';
import 'package:material_ui_packages_migration/features/about/about_page.dart';
import 'package:material_ui_packages_migration/features/releases/releases_page.dart';

void main() {
  testWidgets('the About button opens the About page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('About'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ReleasesPage), findsOneWidget);
    expect(find.byType(AboutPage), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.byType(AboutPage), findsOneWidget);
  });
}
