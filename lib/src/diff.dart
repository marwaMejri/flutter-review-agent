/// One file changed by a pull request, as seen in its diff.
class DiffFile {
  DiffFile(this.path, {this.deleted = false});

  /// Path of the file in the new version, for example `lib/main.dart`. For a
  /// deleted file, its path before the pull request.
  final String path;

  /// Whether the pull request deletes the file. It then has removed lines
  /// only.
  final bool deleted;

  /// Lines of the new version that appear in the diff, added or unchanged.
  ///
  /// GitHub only accepts review comments on these lines.
  final Set<int> commentableLines = <int>{};

  /// Lines of the new version added by the pull request.
  final Set<int> addedLines = <int>{};

  /// The code of the added lines, without the leading `+`.
  final List<String> addedCode = <String>[];

  /// The code of each line of the new version shown in the diff, by line
  /// number, without the leading `+` or space.
  final Map<int, String> newLineText = <int, String>{};

  /// The removed lines, by the number of the new line that follows them.
  final Map<int, List<String>> removedBefore = <int, List<String>>{};

  /// The diff of this file, with the line number of the new version in front
  /// of each line, so the model can cite exact lines.
  final List<String> annotated = <String>[];

  /// The added and unchanged lines of each hunk, with their `+` or space.
  final List<List<String>> hunks = <List<String>>[];

  /// The numbers of the added lines of each hunk, in the same order as
  /// [hunks].
  final List<List<int>> hunkAddedLines = <List<int>>[];

  /// The code of the hunks that add a line: the added lines and the unchanged
  /// lines shown around them. A trigger `around:` is searched there.
  List<String> get aroundCode => <String>[
    for (final List<String> hunk in hunks)
      if (hunk.any((String line) => line.startsWith('+')))
        for (final String line in hunk) line.substring(1),
  ];

  /// The lines [start] to [end] (not included) of [annotated], as a file of
  /// their own, with the added lines they show. A diff too large for one
  /// request is sent in such parts.
  DiffFile part(int start, int end) {
    final DiffFile part = DiffFile(path, deleted: deleted);
    for (final String line in annotated.sublist(start, end)) {
      part.annotated.add(line);
      final int? number = line.length < 5
          ? null
          : int.tryParse(line.substring(0, 5).trim());
      if (number == null) {
        continue;
      }
      final String text = newLineText[number] ?? '';
      part.newLineText[number] = text;
      if (commentableLines.contains(number)) {
        part.commentableLines.add(number);
      }
      if (addedLines.contains(number)) {
        part.addedLines.add(number);
        part.addedCode.add(text);
      }
    }
    return part;
  }
}

final RegExp _hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@');

/// Reads a unified diff, as printed by `git diff`.
///
/// Deleted files are left out: there is nothing left to comment on. See
/// [parseDeletedFiles].
List<DiffFile> parseDiff(String diff) => _parse(diff).files;

/// Reads the files that the diff deletes, with their removed lines. The model
/// gets them to see where moved code comes from. They have no line to
/// comment on.
List<DiffFile> parseDeletedFiles(String diff) => _parse(diff).deleted;

({List<DiffFile> files, List<DiffFile> deleted}) _parse(String diff) {
  final List<DiffFile> files = <DiffFile>[];
  final List<DiffFile> deleted = <DiffFile>[];
  DiffFile? current;
  String? oldPath;
  bool inHunk = false;
  int newLine = 0;

  for (final String rawLine in diff.split('\n')) {
    final String line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    if (line.startsWith('diff --git ')) {
      current = null;
      oldPath = null;
      inHunk = false;
      continue;
    }

    final Match? hunk = _hunkHeader.firstMatch(line);
    if (hunk != null) {
      newLine = int.parse(hunk.group(1)!);
      inHunk = true;
      current?.annotated.add('      | $line');
      current?.hunks.add(<String>[]);
      current?.hunkAddedLines.add(<int>[]);
      continue;
    }

    if (!inHunk) {
      // File header: the new path, or the old one for a deleted file.
      if (line.startsWith('--- ')) {
        final String source = line.substring(4);
        oldPath = source.startsWith('a/') ? source.substring(2) : source;
      } else if (line.startsWith('+++ ')) {
        final String target = line.substring(4);
        if (target != '/dev/null') {
          current = DiffFile(
            target.startsWith('b/') ? target.substring(2) : target,
          );
          files.add(current);
        } else if (oldPath != null && oldPath != '/dev/null') {
          current = DiffFile(oldPath, deleted: true);
          deleted.add(current);
        }
      }
      continue;
    }

    if (current == null) {
      continue;
    }

    if ((line.startsWith('+') || line.startsWith(' ')) &&
        current.hunks.isNotEmpty) {
      current.hunks.last.add(line);
    }
    if (line.startsWith('+')) {
      if (current.hunkAddedLines.isNotEmpty) {
        current.hunkAddedLines.last.add(newLine);
      }
      current.addedLines.add(newLine);
      current.addedCode.add(line.substring(1));
      current.newLineText[newLine] = line.substring(1);
      current.commentableLines.add(newLine);
      current.annotated.add('${_number(newLine)} |$line');
      newLine++;
    } else if (line.startsWith('-')) {
      current.removedBefore
          .putIfAbsent(newLine, () => <String>[])
          .add(line.substring(1));
      current.annotated.add('      |$line');
    } else if (line.startsWith(' ')) {
      current.newLineText[newLine] = line.substring(1);
      current.commentableLines.add(newLine);
      current.annotated.add('${_number(newLine)} |$line');
      newLine++;
    }
    // Other lines, such as "\ No newline at end of file", are ignored.
  }
  files.forEach(_keepReindentedLinesUnchanged);
  return (files: files, deleted: deleted);
}

/// An added line that is a removed line of the same file with other spaces
/// is only re-indented, for example when a widget is wrapped in a `Column`.
/// It is shown as unchanged: the pull request did not write that code, so no
/// remark can be made on it, and it triggers no rule. The removed line that
/// it matches is left out.
void _keepReindentedLinesUnchanged(DiffFile file) {
  final Map<String, int> removed = <String, int>{};
  for (final List<String> lines in file.removedBefore.values) {
    for (final String line in lines) {
      if (line.trim().isNotEmpty) {
        removed.update(line.trim(), (int n) => n + 1, ifAbsent: () => 1);
      }
    }
  }
  final Set<int> reindented = <int>{};
  final Map<String, int> matched = <String, int>{};
  for (final int line in file.addedLines.toList()..sort()) {
    final String code = (file.newLineText[line] ?? '').trim();
    if ((removed[code] ?? 0) > (matched[code] ?? 0)) {
      matched.update(code, (int n) => n + 1, ifAbsent: () => 1);
      reindented.add(line);
    }
  }
  if (reindented.isEmpty) {
    return;
  }

  // Leave out the removed lines that were matched, in order.
  final Map<String, int> toDrop = Map<String, int>.of(matched);
  bool drop(String line) {
    final int left = toDrop[line.trim()] ?? 0;
    if (left == 0) {
      return false;
    }
    toDrop[line.trim()] = left - 1;
    return true;
  }

  for (final MapEntry<int, List<String>> entry
      in file.removedBefore.entries.toList()) {
    entry.value.removeWhere(drop);
    if (entry.value.isEmpty) {
      file.removedBefore.remove(entry.key);
    }
  }
  final Map<String, int> annotatedDrop = Map<String, int>.of(matched);
  final List<String> annotated = <String>[];
  for (final String line in file.annotated) {
    final int? number = int.tryParse(line.substring(0, 5).trim());
    if (number != null && reindented.contains(number)) {
      // `   12 |+code` becomes `   12 | code`.
      annotated.add('${line.substring(0, 7)} ${line.substring(8)}');
    } else if (number == null && line.startsWith('      |-')) {
      final String code = line.substring(8).trim();
      final int left = annotatedDrop[code] ?? 0;
      if (left > 0) {
        annotatedDrop[code] = left - 1;
      } else {
        annotated.add(line);
      }
    } else {
      annotated.add(line);
    }
  }
  file.annotated
    ..clear()
    ..addAll(annotated);

  for (int i = 0; i < file.hunks.length; i++) {
    final List<int> numbers = file.hunkAddedLines[i];
    int next = 0;
    for (int j = 0; j < file.hunks[i].length; j++) {
      if (file.hunks[i][j].startsWith('+')) {
        if (reindented.contains(numbers[next])) {
          file.hunks[i][j] = ' ${file.hunks[i][j].substring(1)}';
        }
        next++;
      }
    }
    numbers.removeWhere(reindented.contains);
  }
  file.addedLines.removeAll(reindented);
  file.addedCode
    ..clear()
    ..addAll(<String>[
      for (final int line in file.addedLines.toList()..sort())
        file.newLineText[line] ?? '',
    ]);
}

String _number(int line) => line.toString().padLeft(5);
