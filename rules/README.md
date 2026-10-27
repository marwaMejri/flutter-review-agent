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
- **Triggers:** the rule is sent to the model only when a line added by the
  pull request contains one of these texts, or, for `file:…`, when a changed
  file path starts with it. A rule with no triggers is always sent. Fewer
  rules make a shorter request, and leave fewer chances for a false remark.

## Rules in v1

| ID | Rule | File | Level |
|---|---|---|---|
| P1 | Expensive work in `build()` | performance.md | issue |
| P2 | `setState` higher in the tree than needed | performance.md | suggestion |
| P3 | A method that returns a widget tree instead of a widget | performance.md | suggestion |
| P5 | A long list built without a builder | performance.md | suggestion |
| P9 | A builder (`AnimatedBuilder`, `ListenableBuilder`, `ValueListenableBuilder`) that rebuilds a subtree that does not change | performance.md | issue |
| B2 | A resource created in `build()` | memory.md | issue |
| MEM1 | An object with `dispose()` that is never disposed | memory.md | issue |
| MEM2 | A `BuildContext` stored in a field | memory.md | issue |
| MEM3 | A long-lived closure that captures `context` | memory.md | issue |
| B4 | A `late` variable checked for initialization | dart.md | issue |
| B5 | A nullable `Future`, `Stream` or collection returned | dart.md | suggestion |
| T3 | A new case with no test that checks it | tests.md | issue |
| T4 | An appearance test that reads the wrong widget | tests.md | issue |
| T5 | An animated navigation tested only at the end | tests.md | suggestion |
| M1 | An `export` of the SDK Material or Cupertino | ../packs/material_ui_migration.md | issue |
| M2 | A dependency that can bring in, or keep out, `material_ui` | ../packs/material_ui_migration.md | issue |
| M3 | A new UI package in a migrated app | ../packs/material_ui_migration.md | suggestion |
| M4 | `MaterialUiCompatibilityBridge` with no reason and no removal plan | ../packs/material_ui_migration.md | issue |

The pack `material_ui_migration` is optional. It is off unless the project
turns it on.
