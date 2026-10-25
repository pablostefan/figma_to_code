import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import 'names.dart';

/// `TokenTable` do `FigmaPolicy`: nome do Figma → código Dart (`DsSpacing.md`, `context.acmeSpacing.md`).
class Tokens {
  Tokens({this.collections = const {}, this.textStyles});

  /// Coleção de variáveis do Figma (`Spacing`) → a classe dela.
  final Map<String, TokenClass> collections;
  final TokenClass? textStyles;

  /// Variável `Coleção/nome` (`Spacing/md`, `Color/text/primary`) → código; null sem correspondência.
  String? variable(String key) {
    final slash = key.indexOf('/');
    return slash < 0 ? null : collections[key.substring(0, slash)]?.code(key.substring(slash + 1));
  }

  /// Algum token vem do tema (`context.…`): o código precisa de `BuildContext` e não é `const`.
  bool get fromTheme => [...collections.values, ?textStyles].any((c) => c.theme);

  /// Estilo de texto (`body/sm`) → código; null sem correspondência.
  String? textStyle(String name) => textStyles?.code(name);

  /// Lê o `TokenTable` da política; null quando não há.
  static Tokens? read(DartObject? table) {
    if (table == null || table.isNull) return null;
    return Tokens(
      collections: {
        for (final MapEntry(:key, :value) in (table.getField('collections')?.toMapValue() ?? const {}).entries)
          key!.toStringValue()!: ?TokenClass.read(value),
      },
      textStyles: TokenClass.read(table.getField('textStyles')),
    );
  }
}

/// Uma classe com um membro por token, e como o código chega nela.
class TokenClass {
  TokenClass(this.prefix, this.byFigma, this.members, {this.theme = false});

  /// Vem do tema (`via`), não de membro estático.
  final bool theme;

  /// `DsSpacing` (membro estático) ou a expressão do tema (`context.acmeSpacing`).
  final String prefix;

  /// Nome do Figma escrito no doc do membro (`` /// `2xs` = 2 ``) → membro.
  final Map<String, String> byFigma;
  final Set<String> members;

  /// Pelo doc do membro; sem ele, pelo nome em camelCase (`text/primary` → `textPrimary`).
  String? code(String name) =>
      switch (byFigma[name] ?? (members.contains(identifier(name)) ? identifier(name) : null)) {
        final member? => '$prefix.$member',
        null => null,
      };

  static TokenClass? read(DartObject? source) {
    final element = source?.getField('type')?.toTypeValue()?.element;
    if (element is! InterfaceElement) return null;
    final members = [
      ...element.fields.where((f) => f.isOriginDeclaration),
      ...element.getters.where((g) => g.isOriginDeclaration),
    ].where((m) => m.isPublic);
    return TokenClass(
      source!.getField('via')?.toStringValue() ?? element.name!,
      {for (final m in members) ?RegExp('`([^`]+)`').firstMatch(m.documentationComment ?? '')?.group(1): m.name!},
      {for (final m in members) m.name!},
      theme: source.getField('via')?.toStringValue() != null,
    );
  }
}

/// A árvore do IR com os tokens já em Dart: `{value, token}`, `sizeTokens` e o estilo dos textos. Token sem
/// correspondência fica com o nome do Figma e o valor (`Spacing/huge (sem Dart, 48)`), para a LLM não adivinhar.
Object? withDartTokens(Object? node, Tokens tokens) => switch (node) {
  {'token': final String token, 'value': final value} => {
    ...node,
    'token': tokens.variable(token) ?? '$token (sem Dart, $value)',
  },
  Map<String, Object?>() => {
    for (final MapEntry(:key, :value) in node.entries)
      key: switch ((key, value)) {
        ('sizeTokens', final Map<String, Object?> sizes) => {
          for (final MapEntry(key: axis, value: token) in sizes.entries)
            axis: tokens.variable(token! as String) ?? '$token (sem Dart)',
        },
        ('text', final Map<String, Object?> text) => _text(text, tokens),
        _ => withDartTokens(value, tokens),
      },
  },
  List<Object?>() => [for (final item in node) withDartTokens(item, tokens)],
  _ => node,
};

Map<String, Object?> _text(Map<String, Object?> text, Tokens tokens) {
  String? style(Object? name) => name is String ? tokens.textStyle(name) ?? '$name (sem Dart)' : null;
  final out = withDartTokens(text, tokens)! as Map<String, Object?>;
  return {
    ...out,
    if (text['style'] != null) 'style': style(text['style']),
    if (out['segments'] case final List<Object?> segments)
      'segments': [
        for (final s in segments.cast<Map<String, Object?>>())
          {...s, if (s['style'] != null) 'style': style(s['style'])},
      ],
  };
}
