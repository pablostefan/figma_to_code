// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';

/// Acima disso, o enum entra cortado na API.
const maxEnumValues = 30;

/// A API pública de um widget do DS lida do código Dart: construtores com parâmetros (tipo, obrigatório, padrão e
/// doc) e os tipos do próprio pacote que eles usam (classes auxiliares e enums), para a LLM montar o widget sem
/// procurar no código do DS.
String widgetApi(InterfaceElement widget) {
  final out = StringBuffer();
  final seen = <InterfaceElement>{widget};
  final pending = <InterfaceElement>[];
  _interface(out, widget, seen, pending);
  // Um nível de tipos auxiliares basta (ex.: DsStatementDay dentro de List<DsStatementDay>).
  for (final aux in List.of(pending)) {
    out.writeln();
    _interface(out, aux, seen, []);
  }
  return out.toString().trimRight();
}

void _interface(StringBuffer out, InterfaceElement e, Set<InterfaceElement> seen, List<InterfaceElement> pending) {
  _doc(out, e.documentationComment, '');
  if (e is EnumElement) {
    final names = e.fields.where((f) => f.isEnumConstant).map((f) => f.name).toList();
    // Enum enorme (ícones de um DS real) afogaria o brief: o começo, o total e onde está a lista inteira.
    out.writeln(
      names.length <= maxEnumValues
          ? 'enum ${e.name} { ${names.join(', ')} }'
          : 'enum ${e.name} { ${names.take(10).join(', ')}, … } // ${names.length} valores; nome do Figma em '
                'camelCase (arrow-up-right → arrowUpRight); lista inteira em ${e.library.source.uri}',
    );
    return;
  }
  final constructors = e.constructors.where((c) => c.isPublic && !c.isAugmentation).toList();
  out.writeln('class ${e.name} {');
  for (final (i, c) in constructors.indexed) {
    if (i > 0) out.writeln();
    _doc(out, c.documentationComment, '  ');
    final name = c.name.isEmpty || c.name == 'new' ? e.name : '${e.name}.${c.name}';
    final params = c.parameters;
    if (params.isEmpty) {
      out.writeln('  ${c.isConst ? 'const ' : ''}$name();');
      continue;
    }
    final positional = params.where((p) => p.isPositional).toList();
    final named = params.where((p) => p.isNamed && p.name != 'key').toList();
    String line(ParameterElement p) => '${p.isRequiredNamed ? 'required ' : ''}${_param(p)},${_comment(p)}';
    final prefix = '  ${c.isConst ? 'const ' : ''}$name(';
    if (positional.isEmpty) {
      // Só nomeados: `Nome({ … });`, como no código.
      out.writeln('$prefix{');
      for (final p in named) {
        out.writeln('    ${line(p)}');
      }
      out.writeln('  });');
    } else {
      out.writeln(prefix);
      for (final p in positional) {
        out.writeln('    ${line(p)}');
      }
      if (named.isNotEmpty) {
        out.writeln('    {');
        for (final p in named) {
          out.writeln('      ${line(p)}');
        }
        out.writeln('    }');
      }
      out.writeln('  );');
    }
    for (final p in params) {
      _collect(p.type, e.library, seen, pending);
    }
  }
  out.writeln('}');
}

String _param(ParameterElement p) =>
    '${p.type.getDisplayString()} ${p.name}${p.defaultValueCode == null ? '' : ' = ${p.defaultValueCode}'}';

/// O doc do parâmetro, ou do campo para `this.x`, numa linha.
String _comment(ParameterElement p) {
  final doc = p.documentationComment ?? (p is FieldFormalParameterElement ? p.field?.documentationComment : null);
  final line = doc?.split('\n').map((l) => l.replaceFirst(RegExp(r'^\s*///\s?'), '')).join(' ').trim();
  return line == null || line.isEmpty ? '' : ' // $line';
}

void _doc(StringBuffer out, String? doc, String indent) {
  if (doc == null) return;
  for (final line in doc.split('\n')) {
    out.writeln('$indent${line.trim()}');
  }
}

/// Tipos do mesmo pacote do widget usados nos parâmetros, inclusive dentro de genéricos e de funções.
void _collect(DartType type, LibraryElement from, Set<InterfaceElement> seen, List<InterfaceElement> pending) {
  if (type is InterfaceType) {
    final e = type.element;
    if (_samePackage(e.library, from) && seen.add(e)) pending.add(e);
    for (final arg in type.typeArguments) {
      _collect(arg, from, seen, pending);
    }
  } else if (type is FunctionType) {
    _collect(type.returnType, from, seen, pending);
    for (final p in type.parameters) {
      _collect(p.type, from, seen, pending);
    }
  }
}

bool _samePackage(LibraryElement a, LibraryElement b) {
  String package(Uri uri) => uri.isScheme('package') ? uri.pathSegments.first : uri.toString();
  return package(a.source.uri) == package(b.source.uri);
}
