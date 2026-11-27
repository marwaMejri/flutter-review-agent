import 'dart_model.dart';
import 'diff.dart';

/// The code of [file] before the pull request, rebuilt from [newSource], its
/// code after the pull request, and its diff: the added lines are left out,
/// and the removed lines are put back where they were.
///
/// It uses the lines as the diff gives them: a re-indented line, which the
/// review shows as unchanged, matches a removed line by its code only, and
/// that line can be in another place of the file.
String oldSource(String newSource, DiffFile file) {
  final List<String> lines = newSource.replaceAll('\r\n', '\n').split('\n');
  final List<String> old = <String>[];
  for (int number = 1; number <= lines.length; number++) {
    old.addAll(file.diffRemovedBefore[number] ?? const <String>[]);
    if (!file.diffAddedLines.contains(number)) {
      old.add(lines[number - 1]);
    }
  }
  final List<int> after = <int>[
    for (final int number in file.diffRemovedBefore.keys)
      if (number > lines.length) number,
  ]..sort();
  for (final int number in after) {
    old.addAll(file.diffRemovedBefore[number]!);
  }
  return old.join('\n');
}

/// The code of a file that the pull request deletes, from its diff.
String deletedSource(DiffFile file) {
  final List<int> numbers = file.diffRemovedBefore.keys.toList()..sort();
  return <String>[
    for (final int number in numbers) ...file.diffRemovedBefore[number]!,
  ].join('\n');
}

/// One change of a pull request, found by comparing the declarations of a
/// file before and after it.
class CodeChange {
  CodeChange({
    required this.kind,
    required this.file,
    required this.declaration,
    this.from,
    this.before,
    this.addedLines = const <int>[],
  });

  /// `added`, `changed`, `removed` or `moved`.
  final String kind;

  /// The file of the declaration: after the pull request, or before it for a
  /// removed declaration.
  final String file;

  /// The declaration after the pull request, or before it when removed.
  final DartDeclaration declaration;

  /// For a moved declaration: the file it comes from.
  final String? from;

  /// The declaration before the pull request: for a changed class, to show
  /// what it extended; for a moved declaration, where it was.
  final DartDeclaration? before;

  /// For a changed declaration: the lines that the pull request adds in it.
  final List<int> addedLines;
}

/// The changes of a pull request, and the files that could not be read.
class ChangeReport {
  ChangeReport({
    required this.changes,
    required this.unread,
    this.directives =
        const <String, ({List<String> added, List<String> removed})>{},
    this.deleted = const <String>{},
  });

  final List<CodeChange> changes;

  /// The `import`, `export` and `part` lines that the pull request adds and
  /// removes, by file.
  final Map<String, ({List<String> added, List<String> removed})> directives;

  /// The Dart files of the diff that the analyzer could not read, with why.
  /// The agent keeps its other checks for them.
  final Map<String, String> unread;

  /// The Dart files that the pull request deletes.
  final Set<String> deleted;
}

String _key(DartDeclaration d) => '${d.owner ?? ''}|${d.kind}|${d.name}';

/// The changes of the Dart files of [files], whose code after the pull
/// request is in [sources], with the files that it deletes in
/// [deletedFiles].
///
/// A declaration is moved when the pull request removes the same code, with
/// the same kind and name, from another place: another class, another file,
/// or a deleted file. The code is compared as the analyzer prints it, so
/// comments, spaces and line breaks do not count.
ChangeReport codeChanges({
  required List<DiffFile> files,
  required Map<String, String> sources,
  List<DiffFile> deletedFiles = const <DiffFile>[],
}) {
  final Map<String, String> unread = <String, String>{};
  final Map<String, DartFile> before = <String, DartFile>{};
  final Map<String, DartFile> after = <String, DartFile>{};
  for (final DiffFile file in files) {
    final String? source = sources[file.path];
    if (!file.path.endsWith('.dart') || source == null) {
      continue;
    }
    final DartFile now = readDartFile(source);
    final DartFile then = readDartFile(oldSource(source, file));
    if (now.error case final String error) {
      unread[file.path] = error;
      continue;
    }
    // Without the version before the pull request, every declaration would
    // look added. A file that the pull request adds was empty before it,
    // which reads with no error.
    if (then.error case final String error) {
      unread[file.path] = 'the version before the pull request, $error';
      continue;
    }
    after[file.path] = now;
    before[file.path] = then;
  }
  for (final DiffFile file in deletedFiles) {
    if (!file.path.endsWith('.dart')) {
      continue;
    }
    final DartFile then = readDartFile(deletedSource(file));
    if (then.error case final String error) {
      unread[file.path] = error;
    } else {
      before[file.path] = then;
    }
  }

  // Everything the pull request removes, by its code: a removed declaration
  // with the same code as an added one is the origin of a move.
  final List<(String, DartDeclaration)> removed = <(String, DartDeclaration)>[];
  final List<(String, DartDeclaration)> added = <(String, DartDeclaration)>[];
  final List<CodeChange> changes = <CodeChange>[];
  final Set<String> paths = <String>{...before.keys, ...after.keys};
  for (final String path in paths) {
    final Map<String, DartDeclaration> old = <String, DartDeclaration>{
      for (final DartDeclaration d
          in before[path]?.declarations ?? const <DartDeclaration>[])
        _key(d): d,
    };
    final Map<String, DartDeclaration> now = <String, DartDeclaration>{
      for (final DartDeclaration d
          in after[path]?.declarations ?? const <DartDeclaration>[])
        _key(d): d,
    };
    final DiffFile? diff = files
        .where((DiffFile f) => f.path == path)
        .firstOrNull;
    for (final MapEntry<String, DartDeclaration> entry in now.entries) {
      final DartDeclaration? previous = old[entry.key];
      if (previous == null) {
        added.add((path, entry.value));
      } else if (previous.source != entry.value.source &&
          !_onlyMembersChanged(previous, entry.value)) {
        changes.add(
          CodeChange(
            kind: 'changed',
            file: path,
            declaration: entry.value,
            before: previous,
            addedLines: <int>[
              for (
                int line = entry.value.startLine;
                line <= entry.value.endLine;
                line++
              )
                if (diff?.addedLines.contains(line) ?? false) line,
            ],
          ),
        );
      }
    }
    for (final MapEntry<String, DartDeclaration> entry in old.entries) {
      if (!now.containsKey(entry.key)) {
        removed.add((path, entry.value));
      }
    }
  }

  final Set<(String, DartDeclaration)> origins = <(String, DartDeclaration)>{};
  for (final (String path, DartDeclaration declaration) in added) {
    final (String, DartDeclaration)? origin = removed
        .where(
          ((String, DartDeclaration) r) =>
              !origins.contains(r) &&
              r.$2.kind == declaration.kind &&
              r.$2.name == declaration.name &&
              r.$2.source == declaration.source,
        )
        .firstOrNull;
    if (origin != null) {
      origins.add(origin);
    }
    changes.add(
      CodeChange(
        kind: origin == null ? 'added' : 'moved',
        file: path,
        declaration: declaration,
        from: origin?.$1,
        before: origin?.$2,
      ),
    );
  }
  for (final (String, DartDeclaration) item in removed) {
    if (!origins.contains(item)) {
      changes.add(
        CodeChange(kind: 'removed', file: item.$1, declaration: item.$2),
      );
    }
  }

  // The members of a moved class move with it, and the members of a removed
  // class go with it: they are not listed again.
  final Set<String> groups = <String>{
    for (final CodeChange change in changes)
      if ((change.kind == 'moved' || change.kind == 'removed') &&
          change.declaration.owner == null)
        '${change.kind}|${change.file}|${change.declaration.name}',
  };
  changes.removeWhere(
    (CodeChange change) =>
        change.declaration.owner != null &&
        groups.contains(
          '${change.kind}|${change.file}|${change.declaration.owner}',
        ),
  );

  final Map<String, ({List<String> added, List<String> removed})> directives =
      <String, ({List<String> added, List<String> removed})>{};
  for (final String path in paths) {
    final List<String> old = before[path]?.directives ?? const <String>[];
    final List<String> now = after[path]?.directives ?? const <String>[];
    final List<String> addedLines = <String>[
      for (final String d in now)
        if (!old.contains(d)) d,
    ];
    final List<String> removedLines = <String>[
      for (final String d in old)
        if (!now.contains(d)) d,
    ];
    if (addedLines.isNotEmpty || removedLines.isNotEmpty) {
      directives[path] = (added: addedLines, removed: removedLines);
    }
  }
  // In each file, in the order of the new version; the removed
  // declarations, whose lines are those of the old version, come last.
  changes.sort((CodeChange a, CodeChange b) {
    final int byFile = a.file.compareTo(b.file);
    if (byFile != 0) {
      return byFile;
    }
    final int byKind = (a.kind == 'removed' ? 1 : 0).compareTo(
      b.kind == 'removed' ? 1 : 0,
    );
    return byKind != 0
        ? byKind
        : a.declaration.startLine.compareTo(b.declaration.startLine);
  });
  return ChangeReport(
    changes: changes,
    unread: unread,
    directives: directives,
    deleted: <String>{
      for (final DiffFile file in deletedFiles)
        if (file.path.endsWith('.dart')) file.path,
    },
  );
}

/// Whether a class or a mixin changed only in its members, which are listed
/// on their own: its name, what it extends, its mixins and its interfaces
/// stay the same.
bool _onlyMembersChanged(DartDeclaration before, DartDeclaration after) {
  if (after.kind != 'class' && after.kind != 'mixin') {
    return false;
  }
  String header(String source) => source.split('{').first;
  return header(before.source) == header(after.source);
}

/// The changes as the log of the agent shows them: the files in order, each
/// with its changed `import` lines, then its changed declarations.
List<String> describeChanges(ChangeReport report) {
  final List<String> files = <String>{
    for (final CodeChange change in report.changes) change.file,
    ...report.directives.keys,
    ...report.deleted,
  }.toList()..sort();
  final List<String> lines = <String>[];
  for (final String file in files) {
    lines.add(file);
    // The imports of a deleted file go with it.
    final ({List<String> added, List<String> removed})? directives =
        report.deleted.contains(file) ? null : report.directives[file];
    if (report.deleted.contains(file)) {
      lines.add('  deleted  file');
    }
    for (final String directive in directives?.added ?? const <String>[]) {
      lines.add('  added    $directive');
    }
    for (final String directive in directives?.removed ?? const <String>[]) {
      lines.add('  removed  $directive');
    }
    for (final CodeChange change in report.changes) {
      if (change.file == file) {
        lines.add(_describe(change));
      }
    }
  }
  for (final MapEntry<String, String> entry in report.unread.entries) {
    lines.add(
      '${entry.key}: not read (${entry.value}); the other checks of the '
      'agent are kept for this file',
    );
  }
  return lines;
}

String _describe(CodeChange change) {
  final DartDeclaration d = change.declaration;
  final String where = d.startLine == d.endLine
      ? 'line ${d.startLine}'
      : 'lines ${d.startLine}-${d.endLine}';
  final String what = switch (d.kind) {
    'class' =>
      'class ${d.name}'
          '${d.superclass == null ? '' : ' extends ${d.superclass}'}',
    'field' || 'variable' =>
      '${d.kind} ${d.fullName}'
          '${d.type == null ? '' : ': ${_short(d.type!)}'}'
          '${d.initializer == null ? '' : ' = ${_short(d.initializer!)}'}',
    _ => '${d.kind} ${d.fullName}',
  };
  final String detail = switch (change.kind) {
    'moved' when change.from == change.file =>
      ', from ${change.before!.fullName}',
    'moved' when change.before!.fullName != d.fullName =>
      ', from ${change.from} (${change.before!.fullName})',
    'moved' => ', from ${change.from}',
    'changed'
        when change.before?.superclass != null &&
            change.before!.superclass != d.superclass =>
      ', which extended ${change.before!.superclass}',
    'changed' when change.addedLines.length == 1 =>
      ', added line ${change.addedLines.single}',
    'changed' when change.addedLines.isNotEmpty =>
      ', added lines ${_ranges(change.addedLines)}',
    _ => '',
  };
  return '  ${change.kind.padRight(8)} $what, $where$detail';
}

/// [code] on one line, cut after 80 characters: a list of 30 maps is not
/// read in a log.
String _short(String code) {
  final String line = code.replaceAll(RegExp(r'\s+'), ' ');
  return line.length <= 80 ? line : '${line.substring(0, 77)}...';
}

/// Line numbers in order, with the lines that follow each other as a range:
/// `3, 5-8, 12`.
String _ranges(List<int> numbers) {
  final List<int> sorted = numbers.toList()..sort();
  final List<String> parts = <String>[];
  int start = sorted.first;
  int end = start;
  for (final int number in sorted.skip(1)) {
    if (number == end + 1) {
      end = number;
      continue;
    }
    parts.add(start == end ? '$start' : '$start-$end');
    start = end = number;
  }
  parts.add(start == end ? '$start' : '$start-$end');
  return parts.join(', ');
}
