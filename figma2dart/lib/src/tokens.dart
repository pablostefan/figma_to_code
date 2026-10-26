// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';

import 'names.dart';

/// `TokenTable` do `FigmaPolicy`: nome do Figma → código Dart (`DsSpacing.md`, `context.acmeSpacing.md`).
class Tokens {
  Tokens({this.collections = const {}, this.scopes = const {}, this.textStyles});

  /// Coleção de variáveis do Figma (`Spacing`) → a classe dela.
  final Map<String, TokenClass> collections;

  /// Caminho no nome, em qualquer coleção (`Colors/Surface`, com a marca `MarcaA` ou `MarcaB` como coleção) → a classe.
  final Map<String, TokenClass> scopes;
  final TokenClass? textStyles;

  /// Variável `Coleção/nome` (`Spacing/md`, `MarcaA/Colors/Surface/primary`) → código; null sem correspondência. Pela
  /// coleção; senão, pelo caminho mais longo em [scopes].
  String? variable(String key) {
    final slash = key.indexOf('/');
    if (slash < 0) return null;
    final name = key.substring(slash + 1);
    if (collections[key.substring(0, slash)] case final collection?) return collection.code(name);
    for (var end = name.lastIndexOf('/'); end > 0; end = name.lastIndexOf('/', end - 1)) {
      if (scopes[name.substring(0, end)] case final scope?) return scope.code(name.substring(end + 1));
    }
    return null;
  }

  /// Algum token vem do tema (`context.…`): o código precisa de `BuildContext` e não é `const`.
  bool get fromTheme =>
      [...collections.values, ...scopes.values, if (textStyles case final styles?) styles].any((c) => c.theme);

  /// Estilo de texto (`body/sm`) → código; null sem correspondência.
  String? textStyle(String name) => textStyles?.code(name);

  /// Lê o `TokenTable` da política; null quando não há.
  static Tokens? read(DartObject? table) {
    if (table == null || table.isNull) return null;
    Map<String, TokenClass> sources(String field) => {
      for (final MapEntry(:key, :value) in (table.getField(field)?.toMapValue() ?? const {}).entries)
        if (TokenClass.read(value) case final tokenClass?) key!.toStringValue()!: tokenClass,
    };
    return Tokens(
      collections: sources('collections'),
      scopes: sources('scopes'),
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

  /// Nome do Figma → membro: os `names` da política (`'02': 'two'`), que valem antes do doc do membro
  /// (`` /// `2xs` = 2 ``).
  final Map<String, String> byFigma;
  final Set<String> members;

  /// Por `names` ou pelo doc do membro; sem eles, pelo nome em camelCase (`text/primary` → `textPrimary`). Membro
  /// que não existe na classe (erro de digitação em `names`) não vira código.
  String? code(String name) => switch (byFigma[name] ?? identifier(name)) {
    final member when members.contains(member) => '$prefix.$member',
    _ => null,
  };

  static TokenClass? read(DartObject? source) {
    final element = source?.getField('type')?.toTypeValue()?.element;
    if (element is! InterfaceElement) return null;
    final members = [
      ...element.fields.where((f) => !f.isAugmentation),
      ...element.accessors.where((a) => a.isGetter && !a.isAugmentation),
    ].where((m) => m.isPublic);
    return TokenClass(
      source!.getField('via')?.toStringValue() ?? element.name,
      {
        for (final m in members)
          if (RegExp('`([^`]+)`').firstMatch(m.documentationComment ?? '')?.group(1) case final figmaName?)
            figmaName: m.name!,
        for (final MapEntry(:key, :value) in (source.getField('names')?.toMapValue() ?? const {}).entries)
          key!.toStringValue()!: value!.toStringValue()!,
      },
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
