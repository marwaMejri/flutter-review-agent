# Test rules

The pipeline already checks that the tests pass and that the changed lines run
during the tests (coverage). These rules check what coverage cannot see: that
a test **verifies** the change.

## T3. A new case with no test that checks it

- **Check:** code added under `lib/`, and the tests in the same pull request.
- **Flag when:** the pull request adds a behavior (a new public method, a new
  branch of an `if` or `switch`, a new screen state, a changed condition or
  computation) and no test in the pull request has an `expect` on that
  behavior. Judge from the pull
  request only: you do not need to see the other tests of the project.
- **Do not flag when:**
  - the change has no behavior to test: a rename, a comment, or a change of
    padding, color or text style only;
  - the pull request moves existing code without changing what it does, for
    example a part of a screen extracted into a new widget. The call that
    replaces the removed lines is part of the move;
  - an existing test already checks it and the pull request shows that test;
  - the file is generated (`*.g.dart`, `*.freezed.dart`, localizations).
- **Decide:**
  1. Does the pull request add a behavior under `lib/`: a new public method, a
     new branch of an `if` or `switch`, a new screen state, a changed condition
     or computation? Answer no for a rename, a comment, a style change (padding,
     color, text style) and a generated file. Answer no for moved code too:
     added code that the pull request removes from another place (lines marked
     `-`), in the same file or in another one. A new method or widget made from
     removed lines, and the call that replaces them, add no behavior. If yes, go
     to step 2. If no, do not flag.
  2. Does a test file of this pull request have an `expect` on that behavior?
     You do not need to see the other tests of the project. If yes, do not flag.
     If no, flag, and put the remark on the added line under `lib/`, never on a
     test file.
- **Bad:** a pull request adds an `if (release.isBeta)` branch that shows a
  "Beta" badge. The tests render the screen with a stable release only: the
  new line runs in no test, or it runs but nothing checks the badge.
- **Good:** a widget test renders a beta release and checks
  `expect(find.text('Beta'), findsOneWidget)`.
- **Why:** coverage says that a line ran, not that its result was checked.
- **Source:** team rule of this project: every case needs a unit test or a
  widget test.
- **Level:** issue
- **Triggers:** `file:lib/`

## T4. An appearance test that reads the wrong widget

- **Check:** tests with an `expect` on a style property: `fontFamily`,
  `fontSize`, `fontWeight`, `color` or `decoration`. Tests that only find a
  widget to tap it or count it are not concerned.
- **Flag when:** the test finds the widget by its type or its position
  instead of by its content, for example `find.byType(RichText).first` or
  `find.byType(DefaultTextStyle)`, and reads the style there: that widget may
  not be the one that draws the text.
- **Do not flag when:** the test finds the widget from its content, for
  example `find.descendant(of: find.text('Settings'), matching:
  find.byType(RichText))`, or finds the span that contains the text. For a
  `Text` built from a string, the root `TextSpan` of its `RichText` holds the
  text and its style, so reading `text.style` there is correct.
- **Decide:**
  1. Does a test of the pull request have an `expect` on `fontFamily`,
     `fontSize`, `fontWeight`, `color` or `decoration`? If yes, go to step 2. If
     no, do not flag.
  2. Was the widget found by its type or its position, such as
     `find.byType(RichText).first` or `find.byType(DefaultTextStyle)`? If yes,
     flag. If no (it was found from its content, with `find.text(...)` or
     `find.descendant(of: find.text(...), ...)`), do not flag.
- **Bad:**

  ```dart
  final RichText text = tester.widget(find.byType(RichText).first);
  expect(text.text.style?.fontFamily, startsWith('Merriweather'));
  ```

- **Good:** find the `RichText` from the text it shows.

  ```dart
  final RichText text = tester.widget(
    find.descendant(
      of: find.text('Settings'),
      matching: find.byType(RichText),
    ),
  );
  expect(text.text.style?.fontFamily, startsWith('Merriweather'));
  ```

- **Why:** a style on a wrapper can be correct while the text inside uses
  another one. The test passes on a broken screen.
- **Source:** measured in [Your packages haven't migrated to material_ui. Can you?](https://github.com/marwaMejri/material_ui_packages_migration), section "The test that lied", and [Text.build](https://api.flutter.dev/flutter/widgets/Text/build.html) (the root `TextSpan` holds `data` and the text style)
- **Level:** issue
- **Triggers:** `fontFamily`, `fontSize`, `fontWeight`, `TextStyle`, `.style`, `.color`, `decoration`

## T5. An animated navigation tested only at the end

- **Check:** tests for navigation between pages, when the pull request
  changes a line that contains `GoRouter`, `GoRoute`, `routes:`,
  `MaterialApp` or `CupertinoApp`, or changes the version of a router package
  (`go_router`, `auto_route`, `beamer`) in `pubspec.yaml`.
- **Flag when:** every navigation test of the pull request calls
  `pumpAndSettle()` right after the tap, and checks only the new page.
- **Do not flag when:**
  - a test also checks the screen in the middle of the transition, after a
    `pump()` with a duration;
  - the pull request changes none of the lines above. A test that navigates is
    not enough to apply this rule.
- **Decide:**
  1. Does the pull request change a line that contains `GoRouter`, `GoRoute`,
     `routes:`, `MaterialApp` or `CupertinoApp`, or the version of a router
     package (`go_router`, `auto_route`, `beamer`)? A test that navigates is not
     enough. If yes, go to step 2. If no, do not flag.
  2. Does every navigation test of the pull request call `pumpAndSettle()` right
     after the tap, and check only the new page? If yes, flag, and put the
     remark on the test line, not on the router. If no (a test checks the screen
     in the middle of the transition, after a `pump()` with a duration), do not
     flag.
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
- **Triggers:** `GoRoute`, `GoRouter`, `Navigator`, `MaterialApp`, `CupertinoApp`, `routes:`, `go_router:`, `auto_route:`, `beamer:`
