import 'dart:io';

import 'packages.dart';

/// One review rule, read from a Markdown file in `rules/` or `packs/`.
class Rule {
  Rule({
    required this.id,
    required this.title,
    required this.text,
    this.triggers = const <String>[],
  });

  /// The rule number, for example `P1` or `MEM2`.
  final String id;

  /// The title after the number, for example `Expensive work in build()`.
  final String title;

  /// The whole section of the rule, as written in the Markdown file, without
  /// its triggers line (the model does not need it).
  final String text;

  /// When the rule is sent to the model. See [isTriggeredBy].
  final List<String> triggers;

  /// `issue` or `suggestion`, from the `Level` line. Null when there is none.
  String? get level => _field('Level');

  /// Where the rule comes from, from the `Source` line, with its Markdown
  /// links. Null when there is none.
  String? get source => _field('Source');

  /// Whether the agent keeps only the first remark of the rule, from the
  /// `Remarks` line.
  bool get onePerPullRequest => _field('Remarks') == 'one per pull request';

  /// Whether the agent keeps one remark of the rule for each field, from a
  /// `Remarks: one per field` line: for MEM2, the field that stores a
  /// `BuildContext` and the line that assigns it are one problem.
  bool get onePerField => _field('Remarks') == 'one per field';

  /// The rules that win on the same line, from the `Not on a line of` line,
  /// for example `B2` for MEM1. Empty when there is none.
  List<String> get notOnLineOf => <String>[
    for (final Match id in RegExp(
      r'[A-Z]+\d+',
    ).allMatches(_field('Not on a line of') ?? ''))
      id.group(0)!,
  ];

  /// The texts that the line of a remark must contain, from a
  /// `Remark line: contains ...` line. Empty when there is none.
  List<String> get remarkLine {
    final String field = _field('Remark line') ?? '';
    return <String>[
      if (field.startsWith('contains'))
        for (final Match code in _code.allMatches(field)) code.group(1)!,
    ];
  }

  /// The text of the test line where a remark of the rule goes, from a
  /// `Remark place: the first added test line that contains ...` line, such
  /// as `pumpAndSettle(` for T5. Null when there is none.
  String? get remarkPlace {
    final String? field = _field('Remark place');
    if (field == null ||
        !field.startsWith('the first added test line that contains')) {
      return null;
    }
    return _code.firstMatch(field)?.group(1);
  }

  /// The text that the line before the [remarkPlace] line should contain,
  /// from `Remark place: ... right after a ...`, such as `tap(` for T5: the
  /// `pumpAndSettle()` that follows a tap, not the one after `pumpWidget`.
  /// Null when there is none.
  String? get remarkPlaceAfter {
    final String? field = _field('Remark place');
    if (remarkPlace == null || !field!.contains(' right after a ')) {
      return null;
    }
    return _code.allMatches(field).elementAtOrNull(1)?.group(1);
  }

  /// Whether a remark of the rule goes to the widget of the `builder` that
  /// reads neither the animation nor the value (see `builderPlaces`), from
  /// `Remark place: the outermost widget of the builder that reads neither
  /// the animation nor the value`.
  bool get remarkOnBuilderChild =>
      _field('Remark place') ==
      'the outermost widget of the builder that reads neither the animation '
          'nor the value';

  /// Whether a remark of the rule is asked again when a test of the pull
  /// request has an added check, or when the only new behavior of the pull
  /// request is a lifecycle method such as `initState()`, and kept only when
  /// the second answer flags it too, from `Confirm: when a test of the pull
  /// request has an added check, or when its only new behavior is a
  /// lifecycle method`.
  bool get confirmWhenChecks =>
      _field('Confirm') ==
      'when a test of the pull request has an added check, or when its only '
          'new behavior is a lifecycle method';

  /// Whether a remark of the rule on a widget around the list goes to the
  /// list widget built with the loop or the `.map` (see `listPlace`), from
  /// `Remark place: the list widget built with the loop or the .map, not a widget around it`.
  bool get remarkOnListWithLoop =>
      _field('Remark place') ==
      'the list widget built with the loop or the `.map`, not a widget '
          'around it';

  /// Whether a remark of the rule on a `Column` or a `Row` needs a
  /// `SingleChildScrollView` in its file, from a `Remark line: a list widget,
  /// or a Column or Row in a file with a SingleChildScrollView` line.
  bool get remarkInScrollView =>
      _field('Remark line') ==
      'a list widget, or a `Column` or `Row` in a file with a '
          '`SingleChildScrollView`';

  /// Whether a remark of the rule must be on an object that its file does
  /// not dispose (see `disposedOnLine`), from a `Remark line: an object that
  /// the file does not dispose` line.
  bool get remarkOnUndisposed =>
      _field('Remark line') == 'an object that the file does not dispose';

  /// Whether a remark of the rule must be in a `build()` method, or in a
  /// method that a `build()` calls, from a `Remark line: in build(), or in a
  /// method that a build() calls` line.
  bool get remarkInBuild =>
      _field('Remark line') ==
      'in `build()`, or in a method that a `build()` calls';

  /// Whether a remark of the rule needs an added line under `lib/` that
  /// shows a behavior (see `showsBehavior`), from an `Only when` line.
  bool get needsBehaviorLine =>
      _field('Only when') == 'an added line under `lib/` shows a behavior';

  /// Whether the line of a remark must declare a method, a function or a
  /// getter whose return type ends with `>?`, from a
  /// `Remark line: a return type that ends with >?` line.
  bool get remarkOnNullableReturn =>
      _field('Remark line') == 'a return type that ends with `>?`';

  /// Whether the first widget of the line of a remark must not be `const`,
  /// from a `Remark line: a widget that is not const` line.
  bool get remarkOnNonConstWidget =>
      _field('Remark line') == 'a widget that is not `const`';

  String? _field(String name) {
    final Match? match = RegExp(
      '^- \\*\\*$name:\\*\\* (.+(?:\\n  .+)*)',
      multiLine: true,
    ).firstMatch(text);
    return match?.group(1)!.replaceAll(RegExp(r'\n  '), ' ').trim();
  }

  /// Whether the rule applies to a pull request that changes [paths] and adds
  /// the lines [addedCode]. [aroundCode] is the code of the hunks that add a
  /// line, unchanged lines included.
  ///
  /// A trigger `file:test/` matches a changed path that starts with `test/`
  /// in its package (see [inPackage]): `test/a_test.dart`, and
  /// `packages/core/test/a_test.dart` in a monorepo.
  /// A trigger `around:GoRoute` matches a hunk that adds a line and contains
  /// `GoRoute`, on an added or an unchanged line. Any other trigger matches an
  /// added line that contains it. A rule without triggers always applies.
  bool isTriggeredBy({
    required List<String> paths,
    required List<String> addedCode,
    List<String> aroundCode = const <String>[],
  }) {
    if (triggers.isEmpty) {
      return true;
    }
    for (final String trigger in triggers) {
      if (trigger.startsWith('file:')) {
        final String prefix = trigger.substring('file:'.length);
        if (paths.any((String path) => inPackage(path).startsWith(prefix))) {
          return true;
        }
      } else if (trigger.startsWith('around:')) {
        final String text = trigger.substring('around:'.length);
        if (aroundCode.any((String line) => line.contains(text))) {
          return true;
        }
      } else if (addedCode.any((String line) => line.contains(trigger))) {
        return true;
      }
    }
    return false;
  }
}

final RegExp _triggersLine = RegExp(
  r'^- \*\*Triggers:\*\*(.*)$',
  multiLine: true,
);
final RegExp _code = RegExp('`([^`]+)`');

final RegExp _ruleHeading = RegExp(r'^## ([A-Z]+\d+)\. (.+)$', multiLine: true);

/// Reads every rule of a Markdown file.
///
/// A rule starts with a heading such as `## P1. Expensive work in build()` and
/// ends at the next rule heading.
List<Rule> parseRules(String markdown) {
  final String text = markdown.replaceAll('\r\n', '\n');
  final List<RegExpMatch> headings = _ruleHeading.allMatches(text).toList();
  return <Rule>[
    for (int i = 0; i < headings.length; i++)
      _ruleFrom(
        headings[i],
        text.substring(
          headings[i].start,
          i + 1 < headings.length ? headings[i + 1].start : text.length,
        ),
      ),
  ];
}

Rule _ruleFrom(RegExpMatch heading, String section) {
  final Match? triggers = _triggersLine.firstMatch(section);
  return Rule(
    id: heading.group(1)!,
    title: heading.group(2)!.trim(),
    text: section.replaceAll(_triggersLine, '').trim(),
    triggers: triggers == null
        ? const <String>[]
        : <String>[
            for (final Match code in _code.allMatches(triggers.group(1)!))
              code.group(1)!,
          ],
  );
}

/// Reads the rules that are always on (every Markdown file of [rulesFolder]
/// except its README), then the optional [packs] from [packsFolder].
///
/// Files are read in alphabetical order, so the order never changes.
List<Rule> readRules({
  required String rulesFolder,
  String packsFolder = 'packs',
  List<String> packs = const <String>[],
}) {
  final List<File> files =
      Directory(rulesFolder)
          .listSync()
          .whereType<File>()
          .where(
            (File file) =>
                file.path.endsWith('.md') && !file.path.endsWith('README.md'),
          )
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));
  return <Rule>[
    for (final File file in files) ...parseRules(file.readAsStringSync()),
    for (final String pack in packs)
      ...parseRules(File('$packsFolder/$pack.md').readAsStringSync()),
  ];
}
