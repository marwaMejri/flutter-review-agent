# Flutter review agent

A GitHub Action that reviews the pull requests of a Flutter project with a
language model. Each remark is written on the line it is about, cites a rule
and its source, and never blocks the pull request.

It is built so that a small model gives the same remarks as a large one:
the agent computes the facts a model could get wrong, and checks every remark
before it is written. Both were measured on the same 45 pull requests (see
[How it was tested](#how-it-was-tested)).

Example: the reviews on the pull requests of
[flutter-review-example](https://github.com/marwaMejri/flutter-review-example/pulls).

## What it checks

The agent checks what a lint cannot. If `dart analyze` can check it, it
belongs in `analysis_options.yaml`, not here.

| ID | Rule | Level |
|---|---|---|
| P1 | Expensive work in `build()` | issue |
| P2 | `setState` higher in the tree than needed | suggestion |
| P3 | A method that returns a widget tree instead of a widget | suggestion |
| P5 | A long list built without a builder | suggestion |
| P9 | A builder that rebuilds a subtree that does not change | issue |
| B2 | A resource created in `build()` | issue |
| MEM1 | An object with `dispose()` that is never disposed | issue |
| MEM2 | A `BuildContext` stored in a field | issue |
| MEM3 | A long-lived closure that captures `context` | issue |
| B4 | A `late` variable checked for initialization | issue |
| B5 | A nullable `Future`, `Stream` or collection returned | suggestion |
| T3 | A new case with no test that checks it | suggestion |
| T4 | An appearance test that reads the wrong widget | issue |
| T5 | An animated navigation tested only at the end | suggestion |

An **issue** has a real cost: a bug, a leak, slower frames. A
**suggestion** is an improvement that the author can decide on, such as a
builder for a list that may be short. Each rule, with its examples and its
source (the Flutter documentation, Effective Dart, or a measurement that is
linked), is in [`rules/`](rules/).

- **Packs** are optional rules for one kind of project. The pack
  [`material_ui_migration`](packs/material_ui_migration.md) (M1 to M4) is for
  an app that moves from the SDK Material library to `material_ui`.
- **Project conventions:** if the project has a `CONVENTIONS.md`, the agent
  checks the added lines against it. The file is read from the base branch,
  so a pull request cannot change the conventions of its own review.

## How it works

1. **Only the rules that apply are sent.** Each rule has triggers, such as
   `setState` for P2. A rule with no trigger in the added lines is not sent:
   the request is shorter, and there are fewer chances for a false remark.
2. **Each rule is a list of yes/no steps**, answered in order. The model gives
   the answer of each step, and the log shows it: a wrong remark shows which
   step to make clearer.
3. **The agent computes the facts that a model could get wrong**, and gives
   them in the request:
   - the test files of the pull request and their added checks (`expect`,
     `verify`, `blocTest` arguments);
   - the added conditions of a widget when no test of the pull request
     renders a widget;
   - for each changed builder, the widget that reads neither the animation
     nor the value;
   - the feature and the layer of each added import;
   - the added lines inside a router (`GoRouter`, `GoRoute`, `MaterialApp`);
   - the added exports of the SDK Material or Cupertino.
4. **The agent checks every remark before it is written:**
   - the line is added by the pull request, and the code that the remark
     cites is on it or next to it;
   - the rule allows a remark on that line: B5 only on a return type that
     ends with `>?`, P1 and B2 only in `build()` or in a method that a
     `build()` of the project calls, never in a callback such as
     `onPressed: () {...}`, P3 only on a method that returns a `Widget`, P5
     only in a list widget, MEM1 never on an object that the file disposes,
     T5 only when the pull request adds a navigation test, a convention about
     a package only on an import;
   - one remark per rule and line, one per pull request for T3 and T5, one
     per field for MEM2.
5. **The agent puts some remarks on the right line:** T5 on the
   `pumpAndSettle()` after the tap, P9 on the widget of the builder that
   reads neither the animation nor the value, P5 on the list built with the
   loop.
6. **Some remarks are confirmed by a second answer.** When a test of the
   pull request has an added check, or when the only new behavior is a
   lifecycle method such as `initState()`, T3 is asked a second time, alone.
   A remark about a project convention is always asked a second time, with
   the conventions alone. The remark is kept only if both answers flag it;
   the review says so.
7. **A pull request too large for the provider** is sent again with the
   changed parts only, then cut between files or between hunks, so that the
   code keeps its context.
8. **Monorepos:** each path is read in its package (`packages/core/lib/` is
   the `lib/` of `packages/core`), and every `pubspec.yaml` is reviewed.

## Use it

Add a job to a workflow of your project:

```yaml
on:
  pull_request:

jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v7
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0
      - uses: marwaMejri/flutter-review-agent@v1
        with:
          provider: gemini
          model: gemini-3.5-flash-lite
          api-key: ${{ secrets.FLUTTER_REVIEW_API_KEY }}
```

| Input | Required | Description |
|---|---|---|
| `api-key` | yes | API key of the provider. Keep it in a secret. |
| `provider` | yes | `gemini`, `groq`, `openai`, or a name for another provider. |
| `model` | no | Model name, or several separated by commas. Empty uses the preset. |
| `base-url` | no | Address of an OpenAI-compatible API, for a provider with no preset. |
| `packs` | no | Packs to turn on, separated by spaces. |
| `conventions` | no | Path of the conventions. Default: `CONVENTIONS.md`. |
| `github-token` | no | Token that writes the review. Default: the token of the workflow. |

Any provider with an OpenAI-compatible API works with `base-url`, a local
model included. When the chosen model is busy or out of quota, the agent
tries the other models of the preset; the review says which model answered.

A busy or exhausted provider gives no review: the job writes why on the pull
request, and does not fail. A review uses one request, a few more for a
large pull request; on the free Groq plan, that is about 20 reviews a day. A pull request from a fork gets no review either:
GitHub does not pass secrets to workflows triggered from a fork
([GitHub docs](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions)).

## Run it on your machine

```sh
dart pub get
git diff main...my-branch > pr.diff
dart run bin/flutter_review.dart --diff pr.diff --project ../my_app \
  --conventions ../my_app/CONVENTIONS.md --provider gemini \
  --model gemini-3.5-flash-lite
```

The key is read from `FLUTTER_REVIEW_API_KEY`. The output shows the remarks,
the remarks refused by the agent with the reason, and the answer of the model
for each rule.

## How it was tested

- **171 unit tests** (`dart test`): one for each check, fact and placement
  of the agent.
- **45 test pull requests** in
  [flutter-review-example](https://github.com/marwaMejri/flutter-review-example/pulls),
  each with its expected remarks written before the run: 21 features of a
  real app (4 with no expected remark), 9 challenges (a prompt injection in
  the code, a generated file, a new file of 448 lines, moved code, traps...)
  and 15 cases at the edge of a rule (a mocktail `verify`, a
  `TweenAnimationBuilder`, a pub workspace...).
- **50 merged pull requests of 8 open-source projects**, written by other
  developers, each remark judged by reading the code:
  [flutter/samples](https://github.com/flutter/samples),
  [immich](https://github.com/immich-app/immich),
  [localsend](https://github.com/localsend/localsend),
  [bloc](https://github.com/felangel/bloc), and 4 blind sets:
  [lichess mobile](https://github.com/lichess-org/mobile) (Riverpod),
  [thunder](https://github.com/thunder-app/thunder) (`flutter_bloc`),
  [ente](https://github.com/ente-io/ente) (a monorepo) and
  [FluffyChat](https://github.com/krille-chan/fluffychat). A blind set is
  picked by a rule written before the run (the most recent merged pull
  requests that change 20 to 400 lines of Dart under `lib/`), and no fix of
  the agent comes from it.
- **Two models:** a small one (`gemini-3.5-flash-lite`, Gemini) and a large
  one (`openai/gpt-oss-120b`, Groq), on the free plans of their providers.
- **Every error is in the log**
  [`eval/real_pull_requests.md`](eval/real_pull_requests.md): the remark, its
  cause read in the answer of the model, the fix, and the run after it.

## Measured results

Agent `v1`. A pull request counts as expected when the review has every
expected remark, on the expected line, and no other remark.

**The 45 test pull requests**

| Model | As expected (first run) | With no false remark |
|---|---|---|
| `gemini-3.5-flash-lite` | 43 out of 44 (98 %) | 44 out of 44 (100 %) |
| `openai/gpt-oss-120b` | 38 out of 45 (84 %) | 43 out of 45 (96 %) |

One pull request of the Gemini run (#5) was answered by another model of
the preset and is not counted. After a second run of the 3 pull requests
that were not as expected or not counted: 45 out of 45.

With `gpt-oss-120b`, the 7 pull requests not as expected are 2 false T3
(suggestions), 4 missed remarks (P5, T5, P9, 2 conventions of one pull
request) and 1 MEM1 added on a stream subscription that is never cancelled
(true, but MEM3 already flags the line). The small model, with the facts and
the checks of the agent, does as well as the large one.

**50 real pull requests, `gemini-3.5-flash-lite`**

| | All 50 | The 25 of the blind sets |
|---|---|---|
| Pull requests with no false remark | 46 (92 %) | 23 (92 %) |
| Remarks right or debatable | 24 out of 28 (86 %) | 15 out of 17 (88 %) |
| Pull requests with no remark, rightly | 22 | 9 |

The 4 false remarks: T3 on a refactor and on wiring code (suggestions), T4
on a test that reads its own style (issue), P5 on the items of a popup menu
(suggestion). Each one is in the log with its cause. 1 remark was missed
(T3, debatable).

The checks that the agent computes give the same result on every run. The
answers that need the judgment of the model change from one run to the
next: P5 on test pull request #5 was found in 3 runs out of 4. The rules
that need the most judgment, T3 above all, are suggestions for that reason.

## License

[MIT](LICENSE)
