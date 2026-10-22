# Test rules

The pipeline already checks that the tests pass and that the changed lines run
during the tests (coverage). These rules check what coverage cannot see: that
a test **verifies** the change.

## T3. A new case with no test that checks it

- **Check:** code added under `lib/`, and the tests in the same pull request.
- **Flag when:** the pull request adds a behavior (a new public method, a new
  branch of an `if` or `switch`, a new screen state, a fixed bug) and no test
  in the pull request has an `expect` on that behavior.
- **Do not flag when:** the change has no behavior to test (a rename, a
  comment, a style change), or an existing test already checks it and the
  pull request shows that test.
- **Bad:** a pull request adds an `if (release.isBeta)` branch that shows a
  "Beta" badge. The tests render the screen with a stable release only: the
  new line runs in no test, or it runs but nothing checks the badge.
- **Good:** a widget test renders a beta release and checks
  `expect(find.text('Beta'), findsOneWidget)`.
- **Why:** coverage says that a line ran, not that its result was checked.
- **Source:** team rule of this project: every case needs a unit test or a
  widget test.
- **Level:** issue

## T4. An appearance test that reads the wrong widget

- **Check:** tests that check a font, a color or a style.
- **Flag when:** the test reads the style from a wrapper (a
  `DefaultTextStyle`, the root `TextSpan` of a `RichText`, a parent
  `Container`) instead of the widget or the span that draws the content.
- **Do not flag when:** the test finds the exact span or widget that holds the
  content, for example by its text.
- **Bad:**

  ```dart
  final RichText text = tester.widget(find.byType(RichText).first);
  expect(text.text.style?.fontFamily, startsWith('Merriweather'));
  ```

- **Good:** find the span that contains the text, and read its style.

  ```dart
  TextStyle? styleOfText(InlineSpan span, String prefix) {
    if (span is TextSpan) {
      if (span.text != null && span.text!.startsWith(prefix)) return span.style;
      for (final InlineSpan child in span.children ?? const <InlineSpan>[]) {
        final TextStyle? style = styleOfText(child, prefix);
        if (style != null) return style;
      }
    }
    return null;
  }
  ```

- **Why:** a style on a wrapper can be correct while the text inside uses
  another one. The test passes on a broken screen.
- **Source:** measured in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration), section "The test that lied"
- **Level:** issue

## T5. An animated navigation tested only at the end

- **Check:** tests for navigation between pages, when the pull request
  changes routing, the router package or the app widget.
- **Flag when:** the only navigation tests tap and then call `pumpAndSettle()`
  before checking the new page.
- **Do not flag when:** a test also checks the screen in the middle of the
  transition.
- **Bad:**

  ```dart
  await tester.tap(find.text('Version 3.0.0'));
  await tester.pumpAndSettle();
  expect(find.byType(ReleaseDetailPage), findsOneWidget);
  ```

- **Good:**

  ```dart
  await tester.tap(find.text('Version 3.0.0'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  // In the middle of the transition, both pages are on screen.
  expect(find.byType(ReleasesPage), findsOneWidget);
  expect(find.byType(ReleaseDetailPage), findsOneWidget);
  ```

- **Why:** the final screen is the same with or without a transition. A test
  that only checks the end cannot see a transition that disappeared.
- **Source:** measured with `go_router` 17.5.0 in a migrated app, in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration)
- **Level:** suggestion
