import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// One declaration of a Dart file, as the Dart analyzer reads it: a class or
/// a mixin, a top-level function or variable, or a member of a class.
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
    this.owner,
    this.superclass,
    this.type,
    this.initializer,
  });

  /// `class`, `mixin`, `function`, `variable`, `method`, `getter`, `setter`,
  /// `field` or `constructor`.
  final String kind;

  /// The name. A constructor with no name has an empty name.
  final String name;

  /// The class or the mixin that holds a member. Null for a top-level
  /// declaration.
  final String? owner;

  /// First line of the declaration, after its doc comment and annotations,
  /// and last line. Lines start at 1.
  final int startLine;
  final int endLine;

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

  /// The name with its owner, such as `HomePage.build`.
  String get fullName => owner == null
      ? name
      : name.isEmpty
      ? owner!
      : '$owner.$name';

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
  DartFile({required this.declarations, required this.directives, this.error});

  /// Its declarations, members included, in the order of the file.
  final List<DartDeclaration> declarations;

  /// Its `import`, `export` and `part` lines, as the analyzer prints them.
  final List<String> directives;

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

  void addMembers(String owner, NodeList<ClassMember> members) {
    for (final ClassMember member in members) {
      if (member is MethodDeclaration) {
        declarations.add(
          DartDeclaration(
            kind: member.isGetter
                ? 'getter'
                : member.isSetter
                ? 'setter'
                : 'method',
            name: member.name.lexeme,
            owner: owner,
            startLine: start(member),
            endLine: end(member),
            source: member.toSource(),
            type: member.returnType?.toSource(),
          ),
        );
      } else if (member is FieldDeclaration) {
        for (final VariableDeclaration field in member.fields.variables) {
          declarations.add(
            DartDeclaration(
              kind: 'field',
              name: field.name.lexeme,
              owner: owner,
              startLine: start(member),
              endLine: end(member),
              source: member.toSource(),
              type: member.fields.type?.toSource(),
              initializer: field.initializer?.toSource(),
            ),
          );
        }
      } else if (member is ConstructorDeclaration) {
        declarations.add(
          DartDeclaration(
            kind: 'constructor',
            name: member.name?.lexeme ?? '',
            owner: owner,
            startLine: start(member),
            endLine: end(member),
            source: member.toSource(),
          ),
        );
      }
    }
  }

  for (final CompilationUnitMember member in result.unit.declarations) {
    if (member is ClassDeclaration) {
      final String name = member.namePart.typeName.lexeme;
      declarations.add(
        DartDeclaration(
          kind: 'class',
          name: name,
          startLine: start(member),
          endLine: end(member),
          source: member.toSource(),
          superclass: member.extendsClause?.superclass.toSource(),
        ),
      );
      addMembers(name, member.body.members);
    } else if (member is MixinDeclaration) {
      final String name = member.name.lexeme;
      declarations.add(
        DartDeclaration(
          kind: 'mixin',
          name: name,
          startLine: start(member),
          endLine: end(member),
          source: member.toSource(),
        ),
      );
      addMembers(name, member.body.members);
    } else if (member is FunctionDeclaration) {
      declarations.add(
        DartDeclaration(
          kind: 'function',
          name: member.name.lexeme,
          startLine: start(member),
          endLine: end(member),
          source: member.toSource(),
          type: member.returnType?.toSource(),
        ),
      );
    } else if (member is TopLevelVariableDeclaration) {
      for (final VariableDeclaration variable in member.variables.variables) {
        declarations.add(
          DartDeclaration(
            kind: 'variable',
            name: variable.name.lexeme,
            startLine: start(member),
            endLine: end(member),
            source: member.toSource(),
            type: member.variables.type?.toSource(),
            initializer: variable.initializer?.toSource(),
          ),
        );
      }
    }
  }

  return DartFile(
    declarations: declarations,
    directives: <String>[
      // `library;` names nothing that a rule checks.
      for (final Directive directive in result.unit.directives)
        if (directive is! LibraryDirective) directive.toSource(),
    ],
  );
}
