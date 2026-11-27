final RegExp _widgetClass = RegExp(
  r'\bclass\s+\w+(?:<[^{]*?>)?\s+extends\s+\w*(?:Widget|State)\b[^{]*\{',
);
final RegExp _conditionOrAction = RegExp(
  r'\bif\s*\(|\bswitch\b|\bcase\b|\s\?\s|^\s*\?\s|\?\?|'
  r'\bon[A-Z]\w*\s*:|\bsetState\s*\(',
);

/// The lines of [source] with a condition or an action (`if`, `? :`, `??`,
/// `switch`, `case`, an `on...:` callback, `setState(`) inside a widget or
/// `State` class: a class that extends a class whose name ends with `Widget`
/// or `State`, such as `StatelessWidget`, `ConsumerWidget` or
/// `State<Counter>`. Comments and the text of strings are left out.
Set<int> widgetConditionLines(String source) {
  final String text = source.replaceAll('\r\n', '\n');
  final String code = _codeOnly(text);
  final List<String> lines = code.split('\n');
  final Set<int> found = <int>{};
  for (final Match match in _widgetClass.allMatches(code)) {
    final int open = match.end - 1;
    final int last = _lineOf(text, _closing(code, open));
    for (int line = _lineOf(text, open); line <= last; line++) {
      if (_conditionOrAction.hasMatch(lines[line - 1])) {
        found.add(line);
      }
    }
  }
  return found;
}

final RegExp _callbackArgument = RegExp(r'\bon[A-Z]\w*\s*:');

/// The lines of [source] inside a function given to a callback argument,
/// such as `onPressed: () { ... }` or `onTap: () => ...`: that code runs
/// when the event happens, not when `build()` runs. A method given by name,
/// as in `onChanged: viewModel.search`, has no lines here.
Set<int> callbackLines(String source) {
  final String text = source.replaceAll('\r\n', '\n');
  final String code = _codeOnly(text);
  final Set<int> lines = <int>{};
  for (final Match argument in _callbackArgument.allMatches(code)) {
    final String value = _argument(code, argument.end);
    final int end = argument.end + value.length;
    if (value.contains('=>') || RegExp(r'\)\s*(async\s*)?\{').hasMatch(value)) {
      final int last = _lineOf(text, end);
      for (int line = _lineOf(text, argument.start); line <= last; line++) {
        lines.add(line);
      }
    }
  }
  return lines;
}

final RegExp _listCall = RegExp(
  r'(?<![\w.])(ListView|GridView(?:\.count|\.extent)?|Column|Row|'
  r'SliverChildListDelegate|SingleChildScrollView)\s*(?:<[^()]*>)?\(',
);
final RegExp _loop = RegExp(
  r'\.(map|expand)\s*(?:<[^()]*>)?\(|\bfor\s*\(|\bList\.generate\s*\(',
);

/// A call of a list widget: its position in the code and its lines.
typedef _ListCall = ({int start, int end, int first, int last});

/// The innermost of [calls], or null when there is none.
_ListCall? _innermost(Iterable<_ListCall> calls) => calls.fold<_ListCall?>(
  null,
  (_ListCall? inner, _ListCall call) =>
      inner == null || call.start > inner.start ? call : inner,
);

/// Whether [line] of [source] is inside a list widget (see [listPlace]), or
/// on the line that opens one: a remark of P5 anywhere else, such as on a
/// `for` in the children of a `Stack`, is about no list.
bool inListWidget(String source, int line) {
  final String text = source.replaceAll('\r\n', '\n');
  final String code = _codeOnly(text);
  return _listCall
      .allMatches(code)
      .any(
        (Match match) =>
            _lineOf(text, match.start) <= line &&
            line <= _lineOf(text, _closing(code, match.end - 1)),
      );
}

/// For P5: the line where a remark on [line] of [source] goes, when the
/// remark is on a widget around the list that is built with a loop or a
/// `.map`. The widgets are `ListView(`, `GridView(`, `GridView.count(`,
/// `GridView.extent(`, `Column(`, `Row(`, `SliverChildListDelegate(` and
/// `SingleChildScrollView(`. The widget of [line] is the one that opens on
/// it, or else the innermost one around it. When a loop or a `.map` has that
/// widget as its innermost one, the remark is already right: null. Otherwise
/// the answer is the first widget inside it that has a loop or a `.map`: in
/// `Column(children: [Text(...), Column(children: items.map(...).toList())])`,
/// the inner `Column`. Null when there is none: the remark stays where it
/// is.
int? listPlace(String source, int line) {
  final String text = source.replaceAll('\r\n', '\n');
  final String code = _codeOnly(text);
  final List<_ListCall> calls = <_ListCall>[
    for (final Match match in _listCall.allMatches(code))
      (
        start: match.start,
        end: _closing(code, match.end - 1),
        first: _lineOf(text, match.start),
        last: _lineOf(text, _closing(code, match.end - 1)),
      ),
  ];
  // The innermost list widget of each loop or `.map`.
  final Set<int> withLoop = <int>{
    for (final Match loop in _loop.allMatches(code))
      if (_innermost(
            calls.where(
              (_ListCall call) =>
                  call.start < loop.start && loop.start < call.end,
            ),
          )
          case final _ListCall inner)
        inner.first,
  };
  final _ListCall? widget =
      calls.where((_ListCall call) => call.first == line).firstOrNull ??
      _innermost(
        calls.where(
          (_ListCall call) => call.first <= line && line <= call.last,
        ),
      );
  if (widget == null) {
    return null;
  }
  if (withLoop.contains(widget.first)) {
    return null;
  }
  final List<int> inside =
      withLoop
          .where((int other) => widget.first <= other && other <= widget.last)
          .toList()
        ..sort();
  return inside.firstOrNull;
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
