import 'dart:io';

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

  String? _field(String name) {
    final Match? match = RegExp(
      '^- \\*\\*$name:\\*\\* (.+(?:\\n  .+)*)',
      multiLine: true,
    ).firstMatch(text);
    return match?.group(1)!.replaceAll(RegExp(r'\n  '), ' ').trim();
  }

  /// Whether the rule applies to a pull request that changes [paths] and adds
  /// the lines [addedCode].
  ///
  /// A trigger `file:test/` matches a changed path that starts with `test/`.
  /// Any other trigger matches an added line that contains it. A rule without
  /// triggers always applies.
  bool isTriggeredBy({
    required List<String> paths,
    required List<String> addedCode,
  }) {
    if (triggers.isEmpty) {
      return true;
    }
    for (final String trigger in triggers) {
      if (trigger.startsWith('file:')) {
        final String prefix = trigger.substring('file:'.length);
        if (paths.any((String path) => path.startsWith(prefix))) {
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
