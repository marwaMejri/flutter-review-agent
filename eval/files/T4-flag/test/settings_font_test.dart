import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:material_ui_packages_migration/app/app.dart';

void main() {
  testWidgets('the settings title uses the Google font', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ReleaseNotesApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final DefaultTextStyle style = tester.widget<DefaultTextStyle>(
      find.byType(DefaultTextStyle).first,
    );
    expect(style.style.fontFamily, startsWith('Merriweather'));
  });
}
