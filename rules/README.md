# Review rules

These are the rules the review agent applies to a pull request.

Each rule is something that only a reviewer can check. If a lint can check it,
it belongs in `analysis_options.yaml`, not here. Each rule has a source, so the
author of the pull request can check it too.

## Rule format

Every rule has the same parts:

- **Check:** what to look for in the diff.
- **Flag when:** the cases to report.
- **Do not flag when:** the cases that look similar but are fine.
- **Decide:** the same cases as numbered questions, answered in order. Each
  question says what to do for "yes" and for "no": go to another step, flag,
  or do not flag. Every model, small or large, follows the same steps, and its
  answer names the step that decided, so a wrong answer shows which step to
  make clearer.
- **Bad / Good:** a short example of each.
- **Why:** the cost of the problem, in one or two sentences.
- **Source:** where the rule comes from.
- **Level:** `issue` (a real cost: a bug, a leak, slower frames) or
  `suggestion` (an improvement the author can decide on).
- **Remarks:** optional. `one per pull request`: the agent keeps the first
  remark of the rule and refuses the others. For a rule about the whole pull
  request, such as a missing test. `one per field`: the agent keeps the first
  remark of the rule for each field, for MEM2: the field that stores a
  `BuildContext` and the line that assigns it are one problem. The model does
  not get this line.
- **Remark line:** optional, applied by the agent to the line of each
  remark of the rule. The model does not get this line. The forms:
  - "contains" and texts: the line must contain one of them.
  - "a return type that ends with `>?`" (B5): the line must declare a method,
    a function or a getter with such a type, not a field or a parameter.
  - "a list widget, or a `Column` or `Row` in a file with a
    `SingleChildScrollView`" (P5): the line must be inside a list widget
    (`ListView(`, `GridView(`, `Column(`, `Row(`,
    `SliverChildListDelegate(`, `SingleChildScrollView(`), or open one, and a
    remark on a `Column` or a `Row` needs a `SingleChildScrollView` in the
    file.
  - "a widget that is not `const`" (P9): the first widget of the line must not
    be `const`.
  - "a method that returns a `Widget`" (P3): the line must declare a method or
    a getter that returns a `Widget`, not a widget class.
  - "in `build()`, or in a method that a `build()` calls" (P1): a remark in
    the body of another method, such as `initState` or `load`, is refused
    when no `build()` of the project names that method. A line in a getter
    or in a method written with `=>` is kept. A remark inside a function
    given to a callback, such as `onPressed: () { ... }`, is refused: that
    code runs when the user taps, not in `build()`.

  A remark on a `///` comment is first moved to the member below it.
- **Remark place:** optional. With "the first added test line that
  contains" and a text, as `pumpAndSettle(` for T5, every remark of the rule
  is moved to that line; with no such line, the remark is refused. With "right after a" and a second text, as `tap(`
  for T5, the first such line whose line before contains the second text is
  taken first: the `pumpAndSettle()` after a tap, not the one after
  `pumpWidget`. With "the outermost widget of the builder that reads neither
  the animation nor the value", as for P9, a remark in the `builder` of an
  `AnimatedBuilder`, a `ListenableBuilder`, a `ValueListenableBuilder` or a
  `TweenAnimationBuilder` is moved to the outermost widget given to
  `child:`, returned or listed in `children:` that is not `const` and reads
  neither the animation, nor the listenable, nor the value, nor the `child`
  parameter; it is refused when the builder has no such widget. With "the
  list widget built with the loop or the `.map`, not a widget around it", as
  for P5, a remark on a `Column`, a `Row`, a list widget or a
  `SingleChildScrollView` that holds the list is moved to the innermost list
  widget around the loop or the `.map`. The model does not get this line.
- **Not on a line of:** optional. The agent refuses a remark of the rule on a
  line that has a remark of one of these rules. MEM1 has `B2`: an object
  created in `build()` is B2, never MEM1. The model does not get this line.
- **Only when:** optional. With "an added line under lib/ shows a
  behavior", as for T3, the agent keeps a remark of the rule only when an
  added line of code under `lib/` has a condition (`if`, `switch`, `? :`,
  `??`), a callback (`onPressed:`), a loop or an operation on a collection
  (`for`, `.where(`, `.map(`), a state change (`setState(`,
  `notifyListeners(`), an `await`, or a new method or getter with a body
  other than `build()`; or when an added line with an operator replaces a
  removed line with an operator, such as `a + b` changed to `a * b`. The
  model does not get this line.
- **Confirm:** optional. With "when a test of the pull request has an added
  check, or when its only new behavior is a lifecycle method", as for T3, a
  remark of the rule is asked again, with the rule alone, in two cases where
  the model judges: a test of the pull request has an added `expect` or
  `verify` (do they test the new code?), or the only added lines that show a
  behavior declare `initState`, `dispose` or another lifecycle method (is it
  a behavior, or wiring?). The remark is kept only when the second answer
  flags it too. This costs one more request, only in these cases. The model
  does not get this line.
- **Triggers:** the rule is sent to the model only when a line added by the
  pull request contains one of these texts, or, for `file:…`, when the path
  of a changed file in its package starts with it: `file:lib/` matches
  `lib/a.dart`, and `packages/core/lib/a.dart` in a monorepo (a package is
  the folder that holds `lib/`, `test/`, `integration_test/` or
  `pubspec.yaml`). For `around:…`, the text can also be on an
  unchanged line shown around an added line in the diff (3 lines by default),
  for example `GoRoute(` above a `name:` that the pull request adds. A rule
  with no triggers is always sent. Fewer rules make a shorter request, and
  leave fewer chances for a false remark.

## Rules in v1

| ID | Rule | File | Level |
|---|---|---|---|
| P1 | Expensive work in `build()` | performance.md | issue |
| P2 | `setState` higher in the tree than needed | performance.md | suggestion |
| P3 | A method that returns a widget tree instead of a widget | performance.md | suggestion |
| P5 | A long list built without a builder | performance.md | suggestion |
| P9 | A builder (`AnimatedBuilder`, `ListenableBuilder`, `ValueListenableBuilder`, `TweenAnimationBuilder`) that rebuilds a subtree that does not change | performance.md | issue |
| B2 | A resource created in `build()` | memory.md | issue |
| MEM1 | An object with `dispose()` that is never disposed | memory.md | issue |
| MEM2 | A `BuildContext` stored in a field | memory.md | issue |
| MEM3 | A long-lived closure that captures `context` | memory.md | issue |
| B4 | A `late` variable checked for initialization | dart.md | issue |
| B5 | A nullable `Future`, `Stream` or collection returned | dart.md | suggestion |
| T3 | A new case with no test that checks it | tests.md | suggestion |
| T4 | An appearance test that reads the wrong widget | tests.md | issue |
| T5 | An animated navigation tested only at the end | tests.md | suggestion |
| M1 | An `export` of the SDK Material or Cupertino | ../packs/material_ui_migration.md | issue |
| M2 | A dependency that can bring in, or keep out, `material_ui` | ../packs/material_ui_migration.md | issue |
| M3 | A new UI package in a migrated app | ../packs/material_ui_migration.md | suggestion |
| M4 | `MaterialUiCompatibilityBridge` with no reason and no removal plan | ../packs/material_ui_migration.md | issue |

The pack `material_ui_migration` is optional. It is off unless the project
turns it on.
