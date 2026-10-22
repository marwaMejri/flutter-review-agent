/// One review rule, read from a Markdown file in `rules/` or `packs/`.
class Rule {
  Rule({required this.id, required this.title, required this.text});

  /// The rule number, for example `P1` or `MEM2`.
  final String id;

  /// The title after the number, for example `Expensive work in build()`.
  final String title;

  /// The whole section of the rule, as written in the Markdown file.
  final String text;
}

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
      Rule(
        id: headings[i].group(1)!,
        title: headings[i].group(2)!.trim(),
        text: text
            .substring(
              headings[i].start,
              i + 1 < headings.length ? headings[i + 1].start : text.length,
            )
            .trim(),
      ),
  ];
}
