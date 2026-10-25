import 'resolve.dart';
import 'tokens.dart';

/// Dicas do `check`: o que parece fora do brief, com a sugestão. **Não reprovam**: a LLM corrige ou explica com
/// `f2d:inferred` na linha (que cala a dica de valor solto dela).
///
/// O `resolve` grava em cada tarefa (`check.json`) o que a tela e os componentes esperam; o `check` compara com os
/// arquivos.

/// Textos fixos de uma árvore (TEXT sem prop ligada): o que a tela ou o componente mostra como está no Figma.
List<String> staticTexts(Json node) => [
  if (node['visible'] != false) ...[
    if (node['text'] case final Json text when (node['bindings'] as Json?)?['characters'] == null)
      text['characters'] as String,
    for (final child in (node['children'] as List? ?? const []).cast<Json>()) ...staticTexts(child),
  ],
];

/// Valor do token no Figma → código Dart dele, com a coleção (para escolher entre `Spacing/md` e `Radius/md`, ambos
/// 12). Cores em `#RRGGBB` (ou `#RRGGBBAA`), números sem `.0`.
Map<String, List<Json>> tokenValues(Json irTokens, Tokens tokens) {
  final out = <String, List<Json>>{};
  for (final MapEntry(:key, value: token) in irTokens.entries.where((e) => e.value is Json)) {
    final code = tokens.variable(key);
    if (code == null) continue;
    (out[_key((token as Json)['value'])] ??= []).add({'code': code, 'collection': key.split('/').first});
  }
  return out;
}

String _key(Object? value) => switch (value) {
  final String s => s.toUpperCase(),
  final num n when n == n.roundToDouble() => '${n.toInt()}',
  _ => '$value',
};

/// Dicas de um arquivo: valor solto (com o token do mesmo valor, quando há) e, conforme [expect], widget a montar
/// ausente, parâmetro proposto ausente e texto do Figma ausente.
List<Json> hintsFor(String file, String source, {Json? expect, Map<String, List<Json>> tokens = const {}}) {
  final hints = <Json>[];
  void add(int line, String kind, String message) =>
      hints.add({'file': file, 'line': ?(line > 0 ? line : null), 'kind': kind, 'message': message});

  final lines = source.split('\n');
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n];
    if (line.trimLeft().startsWith('//') || line.contains('f2d:inferred')) continue;
    for (final m in _color.allMatches(line)) {
      final argb = m[1]!.toUpperCase();
      final hex = argb.startsWith('FF') ? '#${argb.substring(2)}' : '#${argb.substring(2)}${argb.substring(0, 2)}';
      add(n + 1, 'value', 'cor solta `${m[0]}`${_suggest(tokens[hex])}');
    }
    for (final m in _material.allMatches(line)) {
      add(n + 1, 'value', 'cor do Material `${m[0]}`: use a cor do DS');
    }
    for (final (pattern, prefer) in _numbers) {
      for (final m in pattern.allMatches(line)) {
        for (final value in _number.allMatches(m[m.groupCount]!).map((v) => v[0]!).where((v) => num.parse(v) != 0)) {
          final found = tokens[_key(num.parse(value))] ?? const [];
          final preferred = found.where((t) => prefer.any((p) => (t['collection'] as String).contains(p))).toList();
          add(n + 1, 'value', '`$value` solto em `${m[0]}`${_suggest(preferred.isEmpty ? found : preferred)}');
        }
      }
    }
  }

  if (expect != null) {
    for (final widget in (expect['widgets'] as List? ?? const []).cast<Json>()) {
      final name = widget['widget'] as String;
      // Placeholder ainda com o marcador: o `check` já lista o marcador.
      if (!RegExp('\\b$name\\s*[(.<]').hasMatch(source) && !source.contains('→ $name */')) {
        add(
          0,
          'widget',
          '`${widget['component']}` deveria virar `$name` (brief "Componentes a montar"), e não aparece',
        );
      }
    }
    for (final param in (expect['params'] as List? ?? const []).cast<String>()) {
      if (!RegExp('\\bthis\\.$param\\b').hasMatch(source)) {
        add(0, 'param', 'parâmetro proposto `$param` não está no construtor (renomeou? confira os "Usos na tela")');
      }
    }
    for (final text in (expect['texts'] as List? ?? const []).cast<String>()) {
      if (text.trim().isNotEmpty && !source.contains(text)) {
        add(0, 'text', 'texto do Figma não aparece: "$text" (se vem de dados ou de tradução, ignore)');
      }
    }
  }
  return hints;
}

/// Sugestão: o token semântico antes do primitivo de mesmo valor (`DsColors.bg` antes de `DsPrimitives.gray50`).
String _suggest(List<Json>? tokens) => switch (tokens) {
  [_, ...] =>
    ' → use ${([...tokens]..sort((a, b) => _primitive(a) - _primitive(b))).map((t) => '`${t['code']}`').join(' ou ')}',
  _ => ': use um token do DS (nenhum tem esse valor) ou explique com `f2d:inferred`',
};

int _primitive(Json token) => (token['collection'] as String).toLowerCase().contains('primitive') ? 1 : 0;

final _color = RegExp(r'\bColor\(\s*0x([0-9A-Fa-f]{8})\s*\)');
final _material = RegExp(r'\bColors\.\w+');
final _number = RegExp(r'\b\d+(?:\.\d+)?\b');

/// Onde número solto é valor de layout, e qual coleção de token combina com ele.
final _numbers = [
  (RegExp(r'\b(?:Border)?Radius\.circular\(([^)]*)\)'), const ['Radius']),
  (RegExp(r'\bEdgeInsets(?:Directional)?\.\w+\(([^)]*)\)'), const ['Spacing']),
  (
    RegExp(r'\b(?:width|height|spacing|runSpacing|mainAxisSpacing|crossAxisSpacing|gap|size)\s*:\s*(\d+(?:\.\d+)?)\b'),
    const ['Spacing', 'Size'],
  ),
  (RegExp(r'\bfontSize\s*:\s*(\d+(?:\.\d+)?)\b'), const ['Font', 'Type']),
];
