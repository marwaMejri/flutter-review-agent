/// One file changed by a pull request, as seen in its diff.
class DiffFile {
  DiffFile(this.path);

  /// Path of the file in the new version, for example `lib/main.dart`.
  final String path;

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
}

final RegExp _hunkHeader = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@');

/// Reads a unified diff, as printed by `git diff`.
///
/// Deleted files are skipped: there is nothing left to comment on.
List<DiffFile> parseDiff(String diff) {
  final List<DiffFile> files = <DiffFile>[];
  DiffFile? current;
  bool inHunk = false;
  int newLine = 0;

  for (final String rawLine in diff.split('\n')) {
    final String line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    if (line.startsWith('diff --git ')) {
      current = null;
      inHunk = false;
      continue;
    }

    final Match? hunk = _hunkHeader.firstMatch(line);
    if (hunk != null) {
      newLine = int.parse(hunk.group(1)!);
      inHunk = true;
      current?.annotated.add('      | $line');
      continue;
    }

    if (!inHunk) {
      // File header: only the new path matters.
      if (line.startsWith('+++ ')) {
        final String target = line.substring(4);
        if (target != '/dev/null') {
          current = DiffFile(
            target.startsWith('b/') ? target.substring(2) : target,
          );
          files.add(current);
        }
      }
      continue;
    }

    if (current == null) {
      continue;
    }

    if (line.startsWith('+')) {
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
  return files;
}

String _number(int line) => line.toString().padLeft(5);
