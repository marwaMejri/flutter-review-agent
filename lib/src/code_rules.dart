import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'diff.dart';
import 'findings.dart';
import 'packages.dart';

/// What the code of the agent decides for a rule, with no model: whether
/// the rule applies to the pull request, its remarks, and why, for the log.
/// The code says when the rule applies, from the structure of the code: a
/// rule checked by the code has no triggers.
typedef CodeDecision = ({bool applies, List<Finding> findings, String reason});

/// The rules that the code of the agent checks, by ID: a rule with a
/// `Checked by: the code of the agent` line. Each one gets the files of the
/// pull request and their code after it.
final Map<
  String,
  CodeDecision Function(List<DiffFile> files, Map<String, String> sources)
>
codeChecks =
    <
      String,
      CodeDecision Function(List<DiffFile> files, Map<String, String> sources)
    >{'P9': rebuiltSubtrees};

const Set<String> _builders = <String>{
  'AnimatedBuilder',
  'ListenableBuilder',
  'ValueListenableBuilder',
  'TweenAnimationBuilder',
};

/// A widget in the `builder` of an `AnimatedBuilder`, a `ListenableBuilder`,
/// a `ValueListenableBuilder` or a `TweenAnimationBuilder` that reads
/// nothing that changes when the `builder` runs again, and is not `const`
/// (P9). [widget] is its name, such as `DecoratedBox`; [builder] is the
/// kind of builder, and [builderLine] its first line. [childTaken]: the
/// builder already has a `child` argument. [leaf]: the widget has no widget
/// inside it, such as a `Text`: no `child:` or `children:` anywhere inside
/// it, and no function that can build widgets.
typedef StaticWidget = ({
  int line,
  String widget,
  String builder,
  int builderLine,
  bool childTaken,
  bool leaf,
});

/// The widgets of the builders of [source] that P9 is about (see
/// [StaticWidget]), and the widgets that could not be decided, with why.
///
/// What changes when the `builder` runs again: the objects given to
/// `animation:`, `listenable:` or `valueListenable:` (the whole expression,
/// such as `widget.controller`, and the expression of a variable given
/// there), the value and the child parameters of the `builder`, the
/// variables of the `builder` computed from them, and the variables that the
/// code can change while the builder lives (see [_Builder.mutable]). A
/// widget reads them when its code does, or when it calls a method of its
/// class that does; a function given to it, such as `onPressed`, runs later
/// and does not count.
///
/// The widgets are searched from the one that the `builder` returns, down
/// through `child:`, the elements of `children:`, and the two branches of a
/// condition: there, any construction is a widget. The outermost widget that
/// reads nothing that changes is the one given, not the widgets inside it.
({
  List<StaticWidget> widgets,
  List<String> undecided,
  List<({int first, int last})> builders,
})
staticBuilderWidgets(String source) {
  final result = parseString(content: source, throwIfDiagnostics: false);
  final List<StaticWidget> widgets = <StaticWidget>[];
  final List<String> undecided = <String>[];
  final List<({int first, int last})> builders = <({int first, int last})>[];
  if (result.errors.isNotEmpty) {
    return (widgets: widgets, undecided: undecided, builders: builders);
  }
  int line(int offset) => result.lineInfo.getLocation(offset).lineNumber;
  for (final AstNode node in _nodes(result.unit)) {
    final (String, ArgumentList)? call = switch (node) {
      MethodInvocation(:final SimpleIdentifier methodName)
          when _builders.contains(methodName.name) =>
        (methodName.name, node.argumentList),
      InstanceCreationExpression(:final ConstructorName constructorName)
          when _builders.contains(constructorName.type.name.lexeme) =>
        (constructorName.type.name.lexeme, node.argumentList),
      _ => null,
    };
    if (call == null) {
      continue;
    }
    builders.add((first: line(node.offset), last: line(node.end - 1)));
    final _Builder builder = _Builder(call.$1, node, call.$2, result.unit);
    builder.search(
      line,
      (int at, String widget, bool leaf) => widgets.add((
        line: at,
        widget: widget,
        builder: call.$1,
        builderLine: line(node.offset),
        childTaken: _argument(call.$2, 'child') != null,
        leaf: leaf,
      )),
      (int at, String why) => undecided.add('line $at: $why'),
    );
  }
  return (widgets: widgets, undecided: undecided, builders: builders);
}

/// P9 decided by the code: a remark on each widget of a builder that reads
/// nothing that changes (see [staticBuilderWidgets]), when the pull request
/// adds its line. P9 applies when a builder holds a line that the pull
/// request adds, even when the line of the builder itself is unchanged.
CodeDecision rebuiltSubtrees(
  List<DiffFile> files,
  Map<String, String> sources,
) {
  bool applies = false;
  final List<Finding> findings = <Finding>[];
  final List<String> flagged = <String>[];
  final List<String> notes = <String>[];
  for (final DiffFile file in files) {
    final String? source = sources[file.path];
    // The code of the app, not its tests: a test builds its widgets a few
    // times, the cost that P9 is about does not count there.
    if (source == null ||
        !inPackage(file.path).startsWith('lib/') ||
        !_builders.any(source.contains)) {
      continue;
    }
    final ({
      List<StaticWidget> widgets,
      List<String> undecided,
      List<({int first, int last})> builders,
    })
    found = staticBuilderWidgets(source);
    if (!found.builders.any(
      (({int first, int last}) b) =>
          file.addedLines.any((int l) => b.first <= l && l <= b.last),
    )) {
      continue;
    }
    applies = true;
    // One remark for each builder: a builder has one `child`.
    final Map<int, List<StaticWidget>> byBuilder = <int, List<StaticWidget>>{};
    for (final StaticWidget widget in found.widgets) {
      if (!file.addedLines.contains(widget.line)) {
        notes.add(
          '`${widget.widget}` (${file.path}, line ${widget.line}) reads '
          'nothing that changes, but the pull request does not write its line',
        );
        continue;
      }
      flagged.add(
        '`${widget.widget}` (${file.path}, line ${widget.line}) reads '
        'nothing that changes',
      );
      byBuilder
          .putIfAbsent(widget.builderLine, () => <StaticWidget>[])
          .add(widget);
    }
    for (final List<StaticWidget> widgets in byBuilder.values) {
      findings.add(_remark(file, widgets));
    }
    for (final String why in found.undecided) {
      notes.add('not decided in ${file.path}, $why');
    }
  }
  final String found = flagged.isEmpty
      ? 'no widget of a builder written by the pull request reads nothing '
            'that changes'
      : flagged.join('; ');
  return (
    applies: applies,
    findings: findings,
    reason:
        'Checked by the code of the agent: $found.'
        '${notes.isEmpty ? '' : ' ${notes.join('; ')}.'}',
  );
}

/// Every node under [node], [node] included, in the order of the code.
List<AstNode> _nodes(AstNode node) {
  final List<AstNode> nodes = <AstNode>[];
  void walk(AstNode n) {
    nodes.add(n);
    for (final Object child in n.childEntities) {
      if (child is AstNode) {
        walk(child);
      }
    }
  }

  walk(node);
  return nodes;
}

/// Whether [name] is the name of a type, such as `Text` or `_Badge`.
bool _isType(String name) {
  final String bare = name.replaceFirst(RegExp(r'^_+'), '');
  return bare.isNotEmpty && bare[0].toLowerCase() != bare[0];
}

/// The name of the widget that [e] builds, such as `Text` for `Text(...)`,
/// `const Text(...)` or `Image.asset(...)`, or the name of the method for a
/// call of a method of the class, such as `_buildTitle`. Null for anything
/// else.
String? _built(Expression e) {
  switch (e) {
    case InstanceCreationExpression():
      return e.constructorName.type.name.lexeme;
    case MethodInvocation(:final Expression? target):
      final String name = e.methodName.name;
      if (target == null) {
        return name;
      }
      // `Image.asset(...)`, or `prefix.Text(...)`.
      if (target is SimpleIdentifier && _isType(target.name)) {
        return target.name;
      }
      if (target is SimpleIdentifier && _isType(name)) {
        return name;
      }
      return null;
    default:
      return null;
  }
}

ArgumentList? _arguments(Expression e) => switch (e) {
  InstanceCreationExpression() => e.argumentList,
  MethodInvocation() => e.argumentList,
  _ => null,
};

Expression? _argument(ArgumentList arguments, String name) {
  for (final Argument argument in arguments.arguments) {
    if (argument is NamedArgument && argument.name.lexeme == name) {
      return argument.argumentExpression;
    }
  }
  return null;
}

/// The objects that a builder listens to, as code: the expression given to
/// it, the elements of a list (`Listenable.merge([a, b])`), or the
/// arguments of a construction (`CurvedAnimation(parent: _controller)`).
List<String> _listened(Expression e) {
  if (e is ListLiteral) {
    return <String>[
      for (final CollectionElement element in e.elements)
        if (element is Expression) ..._listened(element),
    ];
  }
  if (e is InstanceCreationExpression ||
      (e is MethodInvocation &&
          (e.target == null || e.target is SimpleIdentifier) &&
          _built(e) != null &&
          _isType(_built(e)!))) {
    return <String>[
      for (final Argument argument in _arguments(e)!.arguments)
        ..._listened(argument.argumentExpression),
    ];
  }
  if (e is Identifier || e is PropertyAccess || e is MethodInvocation) {
    return <String>[e.toSource()];
  }
  return <String>[];
}

class _Builder {
  _Builder(this.kind, this.call, this.arguments, this.unit);

  final String kind;
  final AstNode call;
  final ArgumentList arguments;
  final CompilationUnit unit;

  /// The objects that the builder listens to, as code.
  final List<String> listened = <String>[];

  /// The parameters of the `builder` and its variables that change.
  final Set<String> changing = <String>{};

  /// Why widgets could not be decided, given once for each builder.
  final Set<String> _undecided = <String>{};

  /// The methods and getters of the class around the builder, and the
  /// functions of the file, by name.
  final Map<String, FunctionBody> functions = <String, FunctionBody>{};

  /// The getters among [functions]: read without a call.
  final Set<String> getters = <String>{};

  /// The variables that the code can change while the builder lives, so
  /// that a widget that reads one can show a new value when the builder runs
  /// again: a field of the class assigned outside `setState(...)`, a
  /// constructor and the methods followed by a build (`initState`,
  /// `didUpdateWidget`, `didChangeDependencies`, `build`, `reassemble`); a
  /// variable of the functions around the builder assigned in a function
  /// written there, such as a callback; and a variable of the file that is
  /// not `final`.
  final Set<String> mutable = <String>{};

  void search(
    int Function(int offset) line,
    void Function(int line, String widget, bool leaf) found,
    void Function(int line, String why) undecided,
  ) {
    final Expression? function = _argument(arguments, 'builder');
    if (function is! FunctionExpression) {
      if (function != null) {
        undecided(
          line(function.offset),
          'the builder is `${function.toSource()}`, whose code is not here',
        );
      }
      return;
    }
    for (final String name in <String>[
      'animation',
      'listenable',
      'valueListenable',
    ]) {
      if (_argument(arguments, name) case final Expression e) {
        listened.addAll(_listened(e));
      }
    }
    listened.addAll(_aliases());
    final List<String> parameters = <String>[
      for (final FormalParameter p
          in function.parameters?.parameters ?? const <FormalParameter>[])
        p.name?.lexeme ?? '',
    ];
    if ((kind == 'ValueListenableBuilder' || kind == 'TweenAnimationBuilder') &&
        parameters.length >= 2) {
      changing.add(parameters[1]);
    }
    if (parameters.length >= 2) {
      changing.add(parameters.last);
    }
    changing.removeWhere((String name) => RegExp(r'^_*$').hasMatch(name));
    // The names that [scope] assigns where [changes] says the value can
    // change while the builder lives.
    void assigned(AstNode scope, bool Function(AstNode site) changes) {
      for (final AstNode n in _nodes(scope)) {
        final Expression? target = switch (n) {
          AssignmentExpression() => n.leftHandSide,
          PostfixExpression() => n.operand,
          PrefixExpression(:final operator)
              when operator.lexeme == '++' || operator.lexeme == '--' =>
            n.operand,
          _ => null,
        };
        final String? name = switch (target) {
          SimpleIdentifier() => target.name,
          PropertyAccess(target: ThisExpression()) => target.propertyName.name,
          _ => null,
        };
        if (name != null && changes(n)) {
          mutable.add(name);
        }
      }
    }

    const Set<String> rebuilding = <String>{
      'initState',
      'didUpdateWidget',
      'didChangeDependencies',
      'build',
      'reassemble',
      'dispose',
    };
    bool outsideRebuild(AstNode site) {
      for (AstNode? up = site.parent; up != null; up = up.parent) {
        if (up is FunctionExpression &&
            up.parent?.parent is MethodInvocation &&
            (up.parent!.parent! as MethodInvocation).methodName.name ==
                'setState') {
          return false;
        }
        if (up is ConstructorDeclaration) {
          return false;
        }
        if (up is MethodDeclaration) {
          return !rebuilding.contains(up.name.lexeme);
        }
      }
      return true;
    }

    bool inFunction(AstNode site) {
      for (AstNode? up = site.parent; up != null; up = up.parent) {
        if (up is FunctionExpression) {
          return true;
        }
        if (up is FunctionBody && up.parent is! FunctionExpression) {
          return false;
        }
      }
      return false;
    }

    for (final CompilationUnitMember member in unit.declarations) {
      if (member is FunctionDeclaration) {
        functions[member.name.lexeme] = member.functionExpression.body;
        if (member.isGetter) {
          getters.add(member.name.lexeme);
        }
      } else if (member is TopLevelVariableDeclaration &&
          !member.variables.isFinal &&
          !member.variables.isConst) {
        for (final VariableDeclaration v in member.variables.variables) {
          mutable.add(v.name.lexeme);
        }
      }
    }
    for (AstNode? n = call; n != null; n = n.parent) {
      if (n is ClassDeclaration) {
        for (final ClassMember member in n.body.members) {
          if (member is MethodDeclaration) {
            functions[member.name.lexeme] = member.body;
            if (member.isGetter) {
              getters.add(member.name.lexeme);
            }
          }
        }
        assigned(n.body, outsideRebuild);
      } else if (n is FunctionBody && n != function.body) {
        assigned(n, inFunction);
      }
    }

    final List<Expression> returned = <Expression>[];
    final FunctionBody body = function.body;
    if (body is ExpressionFunctionBody) {
      returned.add(body.expression);
    } else if (body is BlockFunctionBody) {
      // The variables of the builder computed from what changes, until no
      // new one is found.
      bool more = true;
      while (more) {
        more = false;
        for (final AstNode n in _nodes(body.block)) {
          if (n is VariableDeclaration &&
              n.initializer != null &&
              !changing.contains(n.name.lexeme) &&
              _reads(n.initializer!, <String>{}) == null) {
            changing.add(n.name.lexeme);
            more = true;
          }
        }
      }
      for (final AstNode n in _nodes(body.block)) {
        if (n is ReturnStatement &&
            n.expression != null &&
            _inBuilder(n, body)) {
          returned.add(n.expression!);
        }
      }
    }
    for (final Expression e in returned) {
      _visit(e, line, found, undecided);
    }
  }

  /// The expressions of the variables of the functions around the builder
  /// that are given to it, such as `widget.controller` for
  /// `final c = widget.controller;` and `animation: c`.
  List<String> _aliases() {
    final List<String> aliases = <String>[];
    for (final String name in listened.where((String l) => !l.contains('.'))) {
      for (AstNode? n = call.parent; n != null; n = n.parent) {
        if (n is! Block) {
          continue;
        }
        for (final Statement statement in n.statements) {
          if (statement is VariableDeclarationStatement) {
            for (final VariableDeclaration v in statement.variables.variables) {
              if (v.name.lexeme == name && v.initializer != null) {
                aliases.addAll(_listened(v.initializer!));
              }
            }
          }
        }
      }
    }
    return aliases;
  }

  /// Whether [n] is in [body] and not in a function inside it.
  bool _inBuilder(AstNode n, FunctionBody body) {
    for (AstNode? up = n.parent; up != null && up != body; up = up.parent) {
      if (up is FunctionExpression) {
        return false;
      }
    }
    return true;
  }

  bool _isListened(String code) => listened.any(
    (String l) =>
        code == l ||
        code.startsWith('$l.') ||
        code.startsWith('$l?.') ||
        code.startsWith('$l!'),
  );

  /// Whether [node] reads something that changes: null when it does, `''`
  /// when it does not, and why when that cannot be known.
  String? _reads(AstNode node, Set<String> seen) {
    String answer = '';
    for (final AstNode n in _nodes(node)) {
      if ((n is Identifier || n is PropertyAccess || n is MethodInvocation) &&
          _isListened(n.toSource())) {
        return null;
      }
      if (n is! SimpleIdentifier) {
        continue;
      }
      final AstNode? parent = n.parent;
      final bool member =
          (parent is PrefixedIdentifier && parent.identifier == n) ||
          (parent is PropertyAccess && parent.propertyName == n) ||
          (parent is MethodInvocation &&
              parent.methodName == n &&
              parent.target != null);
      if (member) {
        continue;
      }
      if (changing.contains(n.name) || mutable.contains(n.name)) {
        return null;
      }
      if (_isType(n.name) || seen.contains(n.name)) {
        continue;
      }
      final bool called = parent is MethodInvocation && parent.methodName == n;
      // A call in a function given to the widget, such as `onPressed: () {
      // ... }`, runs later, not when the builder runs; and a method given
      // without a call, such as `onPressed: _submit`, runs later too.
      if (_inFunction(n, node) ||
          (functions.containsKey(n.name) &&
              !called &&
              !getters.contains(n.name))) {
        continue;
      }
      // A method or a getter of the class, or a function of the file: what
      // it reads counts.
      if (functions[n.name] case final FunctionBody body) {
        final String? inner = _reads(body, <String>{...seen, n.name});
        if (inner == null) {
          return null;
        }
        if (inner.isNotEmpty) {
          answer = inner;
        }
      } else if (called) {
        answer = '`${n.name}()` is not in the file';
      }
    }
    return answer;
  }

  /// Whether [n] is in a function written inside [root].
  bool _inFunction(AstNode n, AstNode root) {
    for (AstNode? up = n.parent; up != null && up != root; up = up.parent) {
      if (up is FunctionExpression) {
        return true;
      }
    }
    return false;
  }

  void _visit(
    CollectionElement e,
    int Function(int offset) line,
    void Function(int line, String widget, bool leaf) found,
    void Function(int line, String why) undecided,
  ) {
    switch (e) {
      case ParenthesizedExpression():
        _visit(e.expression, line, found, undecided);
        return;
      case ConditionalExpression():
        _visit(e.thenExpression, line, found, undecided);
        _visit(e.elseExpression, line, found, undecided);
        return;
      case IfElement():
        _visit(e.thenElement, line, found, undecided);
        if (e.elseElement case final CollectionElement other) {
          _visit(other, line, found, undecided);
        }
        return;
      case Expression():
        break;
      default:
        // A `for` or a `...` in a list: not one widget that can be the child.
        return;
    }
    final String? widget = _built(e);
    if (widget == null ||
        e.inConstantContext ||
        (e is InstanceCreationExpression && e.isConst)) {
      return;
    }
    final String? reads = _reads(e, <String>{});
    if (reads == '') {
      // A leaf has no `child:` or `children:` anywhere inside it, as in
      // `Navigator(pages: [MaterialPage(child: ...)])`, and no function that
      // can build widgets, as in `itemBuilder: (...) => ...`. A call of a
      // method that builds widgets is not a leaf: its tree is not known here.
      final bool leaf =
          _isType(widget) &&
          !_nodes(e).any(
            (AstNode n) =>
                n is FunctionExpression ||
                (n is NamedArgument &&
                    (n.name.lexeme == 'child' || n.name.lexeme == 'children')),
          );
      found(line(e.offset), widget, leaf);
      return;
    }
    // The outermost widget that a call cannot decide is given, once.
    if (reads != null && _undecided.add(reads)) {
      undecided(line(e.offset), '`$widget`: $reads');
    }
    final ArgumentList? arguments = _arguments(e);
    if (arguments == null) {
      return;
    }
    if (_argument(arguments, 'child') case final Expression child) {
      _visit(child, line, found, undecided);
    }
    if (_argument(arguments, 'children') case final ListLiteral children) {
      for (final CollectionElement element in children.elements) {
        _visit(element, line, found, undecided);
      }
    }
  }
}

/// The P9 remark on the first of [widgets], which are in the same builder.
///
/// Its level is `suggestion` when each widget has no widget inside it, such
/// as a `Text`: the Flutter documentation counts the cost of a build in the
/// nodes that it creates ("Minimize the number of nodes transitively created
/// by the build method"), and says that the `child` of a builder "can
/// improve performance significantly in some cases". A subtree keeps the
/// level of the rule.
Finding _remark(DiffFile file, List<StaticWidget> widgets) {
  final StaticWidget first = widgets.first;
  final String builder = first.builder;
  final List<StaticWidget> others = widgets.sublist(1);
  final String what = others.isEmpty
      ? '`${first.widget}` reads'
      : others.length == 1
      ? '`${first.widget}`, and the widget of line ${others.single.line}, '
            'read'
      : '`${first.widget}`, and the widgets of lines '
            '${others.map((StaticWidget w) => w.line).join(', ')}, read';
  final String fix = others.isNotEmpty
      ? 'Only one widget can be the `child` of the `$builder`: build them '
            'once, in variables written before the `$builder`, and use the '
            'variables here.'
      : first.childTaken
      ? 'Build it once, outside the `builder`: the `child` argument of the '
            '`$builder` is already used, so keep it in a variable written '
            'before the `$builder`, and use that variable here.'
      : 'Build it once: give it to the `child` argument of the `$builder`, '
            'and use the `child` parameter of the `builder`.';
  return Finding(
    rule: 'P9',
    file: file.path,
    line: first.line,
    message:
        '$what nothing that changes when the `builder` of this `$builder` '
        'runs again, and ${others.isEmpty ? 'is' : 'are'} not `const`: '
        '${others.isEmpty ? 'it is' : 'they are'} built again each time. '
        '$fix',
    evidence: file.newLineText[first.line]?.trim() ?? '',
    level: widgets.every((StaticWidget w) => w.leaf) ? 'suggestion' : null,
  );
}
