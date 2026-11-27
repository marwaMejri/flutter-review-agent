import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// One declaration of a Dart file, as the Dart analyzer reads it: a type
/// (class, mixin, enum, extension, extension type), a typedef, a top-level
/// function or variable, or a member of a type.
///
/// The agent reads the structure of the code, not its types: it knows that
/// a field is created with `ScrollController()`, not what that class is.
class DartDeclaration {
  DartDeclaration({
    required this.kind,
    required this.name,
    required this.startLine,
    required this.endLine,
    required this.source,
    int? firstLine,
    this.header,
    this.headerEndLine,
    this.owner,
    this.superclass,
    this.type,
    this.initializer,
  }) : firstLine = firstLine ?? startLine;

  /// `class`, `mixin`, `enum`, `extension`, `extension type`, `typedef`,
  /// `function`, `variable`, `method`, `getter`, `setter`, `field` or
  /// `constructor`; `declaration` for a kind of declaration that the agent
  /// does not know, which is still compared and listed.
  final String kind;

  /// The name. A constructor with no name has an empty name, and an
  /// extension with no name is named by its type, such as `on String`.
  final String name;

  /// The type that holds a member. Null for a top-level declaration.
  final String? owner;

  /// First line of the declaration, after its doc comment and annotations,
  /// and last line. Lines start at 1.
  final int startLine;
  final int endLine;

  /// First line of the declaration with its doc comment and annotations.
  final int firstLine;

  /// For a type: its code before its body, annotations included, and for an
  /// enum its values too, as the analyzer reads it. When the header of a
  /// type is the same before and after the pull request, only its members
  /// changed, and they are listed on their own.
  final String? header;

  /// For a type: the last line of its header, which is the line where its
  /// body starts, or for an enum the line of its last value.
  final int? headerEndLine;

  /// The code of the declaration as the analyzer prints it: comments and
  /// spaces are left out, so two copies of the same code have the same
  /// source.
  final String source;

  /// For a class: what it extends, as written, such as `State<HomePage>`.
  final String? superclass;

  /// For a field or a variable: its type as written. For a method, a getter
  /// or a function: its return type as written.
  final String? type;

  /// For a field or a variable: the code of its initial value.
  final String? initializer;

  /// The name with its owner, such as `HomePage.build`, or
  /// `(extension on String).words` in an extension with no name.
  String get fullName {
    if (owner == null) {
      return name;
    }
    final String holder = owner!.startsWith('on ')
        ? '(extension $owner)'
        : owner!;
    return name.isEmpty ? holder : '$holder.$name';
  }

  /// What a class is for Flutter, from what it extends: `widget` for a
  /// `...Widget`, `state` for a `State<...>`. Null otherwise.
  String? get role {
    final String? base = superclass?.split('<').first.split('.').last;
    if (base == null) {
      return null;
    }
    if (base.endsWith('Widget')) {
      return 'widget';
    }
    if (base == 'State' || base.endsWith('State')) {
      return 'state';
    }
    return null;
  }
}

/// A Dart file as the Dart analyzer reads it.
class DartFile {
  DartFile({
    required this.declarations,
    required this.directives,
    this.codeLines = const <int>{},
    this.declaredLines = const <int>{},
    this.error,
  });

  /// Its declarations, members included, in the order of the file.
  final List<DartDeclaration> declarations;

  /// Its `import`, `export` and `part` lines, as the analyzer prints them.
  final List<String> directives;

  /// The lines that hold code: not only spaces or comments.
  final Set<int> codeLines;

  /// The lines of its declarations and of its `import` lines. The members
  /// of a type cover the lines of its body.
  final Set<int> declaredLines;

  /// The lines of [lines] that hold code and are in no declaration and in no
  /// `import` line. With every kind of declaration read, there should be
  /// none: the agent shows them, so that no change is left out unseen.
  List<int> outsideDeclarations(Iterable<int> lines) => <int>[
    for (final int line in lines)
      if (codeLines.contains(line) && !declaredLines.contains(line)) line,
  ]..sort();

  /// Why the file could not be read, with the line, such as
  /// `line 12: Expected to find ';'`. The file then has no declaration.
  final String? error;
}

/// Reads [content], the code of a Dart file, with the Dart analyzer.
///
/// The file is only parsed: its imports are not followed and its types are
/// not known, so a file reads in about a millisecond, with no Flutter SDK
/// and no package of the project. A file with a syntax error gives a
/// [DartFile.error] and no declaration.
DartFile readDartFile(String content) {
  final ParseStringResult result = parseString(
    content: content,
    throwIfDiagnostics: false,
  );
  int line(int offset) => result.lineInfo.getLocation(offset).lineNumber;
  if (result.errors.isNotEmpty) {
    return DartFile(
      declarations: const <DartDeclaration>[],
      directives: const <String>[],
      error:
          'line ${line(result.errors.first.offset)}: '
          '${result.errors.first.message}',
    );
  }

  final List<DartDeclaration> declarations = <DartDeclaration>[];
  int start(AnnotatedNode node) =>
      line(node.firstTokenAfterCommentAndMetadata.offset);
  int end(AstNode node) => line(node.end > 0 ? node.end - 1 : 0);

  // The code of a type before its body, as tokens: spaces, line breaks and
  // comments do not count.
  String header(
    AnnotatedNode node,
    AstNode body, [
    List<AstNode> values = const <AstNode>[],
  ]) {
    final List<String> words = <String>[];
    for (
      Token? token = node.metadata.isEmpty
          ? node.firstTokenAfterCommentAndMetadata
          : node.metadata.first.beginToken;
      token != null && token != body.beginToken && !token.isEof;
      token = token.next
    ) {
      words.add(token.lexeme);
    }
    return <String>[
      ...words,
      for (final AstNode value in values) value.toSource(),
    ].join(' ');
  }

  DartDeclaration declaration(
    AnnotatedNode node,
    String kind,
    String name, {
    String? owner,
    String? superclass,
    String? type,
    String? initializer,
    AstNode? body,
    List<AstNode> values = const <AstNode>[],
  }) => DartDeclaration(
    kind: kind,
    name: name,
    owner: owner,
    startLine: start(node),
    endLine: end(node),
    firstLine: line(node.offset),
    source: node.toSource(),
    superclass: superclass,
    type: type,
    initializer: initializer,
    header: body == null ? null : header(node, body, values),
    headerEndLine: body == null
        ? null
        : values.isEmpty
        ? line(body.offset)
        : end(values.last),
  );

  void addMembers(String owner, NodeList<ClassMember> members) {
    for (final ClassMember member in members) {
      // ClassMember is sealed: a new kind of member would not compile here.
      switch (member) {
        case MethodDeclaration():
          declarations.add(
            declaration(
              member,
              member.isGetter
                  ? 'getter'
                  : member.isSetter
                  ? 'setter'
                  : 'method',
              member.name.lexeme,
              owner: owner,
              type: member.returnType?.toSource(),
            ),
          );
        case FieldDeclaration():
          for (final VariableDeclaration field in member.fields.variables) {
            declarations.add(
              declaration(
                member,
                'field',
                field.name.lexeme,
                owner: owner,
                type: member.fields.type?.toSource(),
                initializer: field.initializer?.toSource(),
              ),
            );
          }
        case ConstructorDeclaration():
          declarations.add(
            declaration(
              member,
              'constructor',
              member.name?.lexeme ?? '',
              owner: owner,
            ),
          );
        case PrimaryConstructorBody():
          declarations.add(
            declaration(member, 'constructor', 'this', owner: owner),
          );
      }
    }
  }

  // Two extensions with no name on the same type get a number.
  final Map<String, int> unnamed = <String, int>{};
  for (final CompilationUnitMember member in result.unit.declarations) {
    switch (member) {
      case ClassDeclaration():
        final String name = member.namePart.typeName.lexeme;
        declarations.add(
          declaration(
            member,
            'class',
            name,
            superclass: member.extendsClause?.superclass.toSource(),
            body: member.body,
          ),
        );
        addMembers(name, member.body.members);
      case MixinDeclaration():
        final String name = member.name.lexeme;
        declarations.add(declaration(member, 'mixin', name, body: member.body));
        addMembers(name, member.body.members);
      case EnumDeclaration():
        final String name = member.namePart.typeName.lexeme;
        declarations.add(
          declaration(
            member,
            'enum',
            name,
            body: member.body,
            values: member.body.constants,
          ),
        );
        addMembers(name, member.body.members);
      case ExtensionDeclaration():
        String name =
            member.name?.lexeme ??
            'on ${member.onClause?.extendedType.toSource() ?? ''}';
        if (member.name == null) {
          final int count = unnamed[name] = (unnamed[name] ?? 0) + 1;
          if (count > 1) {
            name = '$name ($count)';
          }
        }
        declarations.add(
          declaration(member, 'extension', name, body: member.body),
        );
        addMembers(name, member.body.members);
      case ExtensionTypeDeclaration():
        final String name = member.namePart.typeName.lexeme;
        declarations.add(
          declaration(member, 'extension type', name, body: member.body),
        );
        addMembers(name, member.body.members);
      case ClassTypeAlias():
        declarations.add(
          declaration(
            member,
            'class',
            member.name.lexeme,
            superclass: member.superclass.toSource(),
          ),
        );
      case TypeAlias():
        declarations.add(declaration(member, 'typedef', member.name.lexeme));
      case FunctionDeclaration():
        declarations.add(
          declaration(
            member,
            'function',
            member.name.lexeme,
            type: member.returnType?.toSource(),
          ),
        );
      case TopLevelVariableDeclaration():
        for (final VariableDeclaration variable in member.variables.variables) {
          declarations.add(
            declaration(
              member,
              'variable',
              variable.name.lexeme,
              type: member.variables.type?.toSource(),
              initializer: variable.initializer?.toSource(),
            ),
          );
        }
      default:
        // A kind of declaration that this agent does not know: it is kept,
        // named by the start of its code, so that its changes are listed.
        final String code = member.toSource().split('\n').first;
        declarations.add(
          declaration(
            member,
            'declaration',
            code.length <= 40 ? code : '${code.substring(0, 40)}...',
          ),
        );
    }
  }

  final Set<int> codeLines = <int>{};
  for (
    Token token = result.unit.beginToken;
    !token.isEof;
    token = token.next!
  ) {
    final int last = line(
      token.end > token.offset ? token.end - 1 : token.offset,
    );
    for (int number = line(token.offset); number <= last; number++) {
      codeLines.add(number);
    }
  }

  // A type covers its header and its last line; its members cover its
  // body.
  final Set<int> declaredLines = <int>{};
  void cover(int from, int to) {
    for (int number = from; number <= to; number++) {
      declaredLines.add(number);
    }
  }

  for (final Directive directive in result.unit.directives) {
    cover(line(directive.offset), end(directive));
  }
  for (final DartDeclaration d in declarations) {
    if (d.headerEndLine case final int headerEnd) {
      cover(d.firstLine, headerEnd);
      cover(d.endLine, d.endLine);
    } else {
      cover(d.firstLine, d.endLine);
    }
  }

  return DartFile(
    declarations: declarations,
    // `library;` names nothing that a rule checks.
    directives: <String>[
      for (final Directive directive in result.unit.directives)
        if (directive is! LibraryDirective) directive.toSource(),
    ],
    codeLines: codeLines,
    declaredLines: declaredLines,
  );
}
