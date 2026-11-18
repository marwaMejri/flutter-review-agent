/// The `builder` of an `AnimatedBuilder`, a `ListenableBuilder` or a
/// `ValueListenableBuilder`: its first and last line, and the line of the
/// widget that P9 is about.
typedef BuilderPlace = ({int first, int last, int? line});

final RegExp _builderCall = RegExp(
  r'\b(AnimatedBuilder|ListenableBuilder|ValueListenableBuilder)\s*'
  r'(?:<[^()]*>)?\(',
);
final RegExp _childPosition = RegExp(r'(child:|=>|return|\[|,|\?|\s:)$');
final RegExp _widgetCall = RegExp(
  r'(?<![\w.])(const\s+)?([A-Z]\w*(?:\.\w+)?)\s*(?:<[^()]*>)?\(',
);

/// The builders of [source] (see [BuilderPlace]). The line is the one of the
/// outermost widget in the `builder` function that is not `const` and reads
/// neither the animation, nor the listenable, nor the value: the subtree that
/// can be built once and passed as `child`. It is null when there is none.
List<BuilderPlace> builderPlaces(String source) {
  final String text = source.replaceAll('\r\n', '\n');
  final String code = _codeOnly(text);
  final List<BuilderPlace> places = <BuilderPlace>[];
  for (final Match builder in _builderCall.allMatches(code)) {
    final int open = code.indexOf('(', builder.start);
    final int close = _closing(code, open);
    final String call = code.substring(open, close + 1);
    final Set<String> reads = <String>{
      for (final Match argument in RegExp(
        r'\b(animation|listenable|valueListenable)\s*:',
      ).allMatches(call))
        ..._chainEnds(_argument(call, argument.end)),
    };
    final Match? parameters = RegExp(
      r'\bbuilder\s*:\s*\(([^)]*)\)',
    ).firstMatch(call);
    if (parameters == null) {
      continue;
    }
    final List<String> names = <String>[
      for (final String parameter in parameters.group(1)!.split(','))
        if (parameter.trim().isNotEmpty)
          parameter.trim().split(RegExp(r'\s+')).last,
    ];
    if (builder.group(1) == 'ValueListenableBuilder' && names.length >= 2) {
      reads.add(names[1]);
    }
    // The child parameter: a subtree that holds it cannot be the child.
    if (names.length >= 2) {
      reads.add(names.last);
    }
    // The `builder` function: from its parameters to the next argument.
    final int start = open + parameters.end;
    int end = start;
    int depth = 0;
    for (; end < close; end++) {
      final String char = code[end];
      if ('([{'.contains(char)) {
        depth++;
      } else if (')]}'.contains(char)) {
        depth--;
      } else if (char == ',' && depth == 0) {
        break;
      }
    }
    places.add((
      first: _lineOf(text, builder.start),
      last: _lineOf(text, close),
      line: _staticWidget(code, text, start, end, reads, inConst: false),
    ));
  }
  return places;
}

/// The expression of the argument that starts at [from] in [call], up to the
/// next comma at its level, or the end of the call.
String _argument(String call, int from) {
  int depth = 0;
  int end = from;
  for (; end < call.length - 1; end++) {
    final String char = call[end];
    if ('([{'.contains(char)) {
      depth++;
    } else if (')]}'.contains(char)) {
      if (depth == 0) {
        break;
      }
      depth--;
    } else if (char == ',' && depth == 0) {
      break;
    }
  }
  return call.substring(from, end);
}

/// The names that end a chain in [expression]: `unread` in
/// `context.read<ReleasesViewModel>().unread`, `_controller` in
/// `_controller`. A type, `context`, `this`, and a name followed by `.`, `(`
/// or `<` are left out.
Iterable<String> _chainEnds(String expression) sync* {
  for (final Match name in RegExp(r'[A-Za-z_$][\w$]*').allMatches(expression)) {
    final String text = name.group(0)!;
    final String rest = expression.substring(name.end).trimLeft();
    if (text[0].toUpperCase() == text[0] && text[0] != '_' && text[0] != r'$' ||
        text == 'context' ||
        text == 'this' ||
        rest.startsWith('.') ||
        rest.startsWith('(') ||
        rest.startsWith('<')) {
      continue;
    }
    yield text;
  }
}

/// The line of the outermost widget between [from] and [to] that is not
/// `const` and reads none of [reads]: the widgets that read one are searched
/// inside.
int? _staticWidget(
  String code,
  String text,
  int from,
  int to,
  Set<String> reads, {
  required bool inConst,
}) {
  int position = from;
  while (position < to) {
    final Match? widget = _widgetCall
        .allMatches(code, position)
        .where((Match m) => m.end <= to)
        .firstOrNull;
    if (widget == null) {
      return null;
    }
    final int open = widget.end - 1;
    final int close = _closing(code, open);
    // A widget given to `child:`, returned, or in a list of children. Other
    // calls, such as `BoxDecoration(` after `decoration:`, are skipped.
    if (!_childPosition.hasMatch(code.substring(0, widget.start).trimRight())) {
      position = close + 1;
      continue;
    }
    final bool isConst = widget.group(1) != null || inConst;
    final String span = code.substring(widget.start, close + 1);
    final bool readsValue = reads.any(
      // `child:` is the name of an argument, not the child parameter.
      (String name) =>
          RegExp('\\b${RegExp.escape(name)}\\b(?!\\s*:)').hasMatch(span),
    );
    if (!readsValue && !isConst) {
      return _lineOf(text, widget.start + (widget.group(1)?.length ?? 0));
    }
    if (readsValue) {
      final int? inner = _staticWidget(
        code,
        text,
        open + 1,
        close,
        reads,
        inConst: isConst,
      );
      if (inner != null) {
        return inner;
      }
    }
    position = close + 1;
  }
  return null;
}

/// The position of the bracket that closes the one at [at].
int _closing(String code, int at) {
  int depth = 0;
  for (int i = at; i < code.length; i++) {
    if ('([{'.contains(code[i])) {
      depth++;
    } else if (')]}'.contains(code[i]) && --depth == 0) {
      return i;
    }
  }
  return code.length - 1;
}

int _lineOf(String text, int position) =>
    '\n'.allMatches(text.substring(0, position)).length + 1;

/// [text] with the comments and the text of the strings replaced by spaces,
/// at the same positions. The interpolations of a string, `$count` and
/// `${a.b}`, are kept: they read code.
String _codeOnly(String text) {
  final List<String> out = text.split('');
  void blank(int from, int to) {
    for (int k = from; k < to; k++) {
      if (out[k] != '\n') {
        out[k] = ' ';
      }
    }
  }

  int i = 0;
  final int n = text.length;
  while (i < n) {
    if (text.startsWith('//', i)) {
      final int end = text.indexOf('\n', i);
      blank(i, end < 0 ? n : end);
      i = end < 0 ? n : end;
    } else if (text.startsWith('/*', i)) {
      final int end = text.indexOf('*/', i + 2);
      blank(i, end < 0 ? n : end + 2);
      i = end < 0 ? n : end + 2;
    } else if (text[i] == "'" || text[i] == '"') {
      final bool raw = i > 0 && text[i - 1] == 'r';
      final String quote = text.startsWith(text[i] * 3, i)
          ? text[i] * 3
          : text[i];
      int k = i + quote.length;
      while (k < n && !text.startsWith(quote, k)) {
        if (text[k] == r'\' && !raw) {
          k++;
        }
        k++;
      }
      final int stringEnd = k + quote.length > n ? n : k + quote.length;
      final int contentEnd = stringEnd - quote.length > i + quote.length
          ? stringEnd - quote.length
          : i + quote.length;
      int j = i + quote.length;
      while (j < contentEnd) {
        if (text[j] == r'$' &&
            !raw &&
            j + 1 < contentEnd &&
            text[j + 1] == '{') {
          int depth = 0;
          while (j < contentEnd) {
            if (text[j] == '{') {
              depth++;
            } else if (text[j] == '}' && --depth == 0) {
              j++;
              break;
            }
            j++;
          }
        } else if (text[j] == r'$' && !raw) {
          j++;
          while (j < contentEnd && RegExp(r'[A-Za-z0-9_]').hasMatch(text[j])) {
            j++;
          }
        } else {
          blank(j, j + 1);
          j++;
        }
      }
      i = stringEnd;
    } else {
      i++;
    }
  }
  return out.join();
}
