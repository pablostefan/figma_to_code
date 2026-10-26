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

  // O arquivo inteiro, não linha a linha: o `dart format` quebra chamadas longas (`EdgeInsets.only(\n left: 12,`).
  final lines = source.split('\n');
  int lineOf(int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;
  bool silenced(int line) => lines[line - 1].trimLeft().startsWith('//') || lines[line - 1].contains('f2d:inferred');
  String shown(String code) => code.replaceAll(RegExp(r'\s+'), ' ');

  for (final m in _color.allMatches(source)) {
    final line = lineOf(m.start);
    if (silenced(line)) continue;
    final argb = m[1]!.toUpperCase();
    final hex = argb.startsWith('FF') ? '#${argb.substring(2)}' : '#${argb.substring(2)}${argb.substring(0, 2)}';
    add(line, 'value', 'cor solta `${m[0]}`${_suggest(tokens[hex])}');
  }
  for (final m in _material.allMatches(source)) {
    if (!silenced(lineOf(m.start))) add(lineOf(m.start), 'value', 'cor do Material `${m[0]}`: use a cor do DS');
  }
  for (final (pattern, prefer, onlyWithToken) in _numbers) {
    for (final m in pattern.allMatches(source)) {
      final group = m[m.groupCount]!;
      final groupStart = m.start + m[0]!.lastIndexOf(group);
      for (final v in _number.allMatches(group).where((v) => num.parse(v[0]!) != 0)) {
        final line = lineOf(groupStart + v.start);
        if (silenced(line)) continue;
        final found = tokens[_key(num.parse(v[0]!))] ?? const [];
        final preferred = found.where((t) => prefer.any((p) => (t['collection'] as String).contains(p))).toList();
        if (onlyWithToken && preferred.isEmpty) continue; // `size: 12` não é `DsSpacing.md` só por valer 12
        add(line, 'value', '`${v[0]}` solto em `${shown(m[0]!)}`${_suggest(preferred.isEmpty ? found : preferred)}');
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
    // Texto escrito certo em Dart tem escape (`'R\$ 150,00'`, `'d\'água'`): compara sem ele.
    final plain = source.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1] == 'n' ? '\n' : m[1]!);
    for (final text in (expect['texts'] as List? ?? const []).cast<String>().toSet()) {
      if (text.trim().isNotEmpty && !plain.contains(text)) {
        add(0, 'text', 'texto do Figma não aparece: "$text" (se vem de dados ou de tradução, ignore)');
      }
    }
  }
  // Na ordem do arquivo; as dicas sem linha (o que falta no arquivo todo) no fim.
  return hints..sort((a, b) => ((a['line'] as int?) ?? 1 << 30).compareTo((b['line'] as int?) ?? 1 << 30));
}

/// Sugestão: o token semântico antes do primitivo de mesmo valor (`DsColors.bg` antes de `DsPrimitives.gray50`).
String _suggest(List<Json>? tokens) => switch (tokens) {
  [_, ...] =>
    ' → use ${([...tokens]..sort((a, b) => _primitive(a) - _primitive(b))).map((t) => '`${t['code']}`').join(' ou ')}',
  // O export só traz os tokens que a tela usa: o DS pode ter um com esse valor.
  _ => ': nenhum token usado nesta tela tem esse valor; procure no DS (`search`) ou explique com `f2d:inferred`',
};

int _primitive(Json token) => (token['collection'] as String).toLowerCase().contains('primitive') ? 1 : 0;

final _color = RegExp(r'\bColor\(\s*0x([0-9A-Fa-f]{8})\s*\)');
final _material = RegExp(r'\bColors\.\w+');
final _number = RegExp(r'\b\d+(?:\.\d+)?\b');

/// Onde número solto é valor de layout, qual coleção de token combina com ele e se só vale dar dica quando há
/// token dessa coleção com o valor (`size:` de ícone sem token de tamanho é o tamanho do Figma que o brief manda
/// passar).
final _numbers = [
  (RegExp(r'\b(?:Border)?Radius\.circular\(([^)]*)\)'), const ['Radius'], false),
  (RegExp(r'\bEdgeInsets(?:Directional)?\.\w+\(([^)]*)\)'), const ['Spacing'], false),
  (
    RegExp(r'\b(?:width|height|spacing|runSpacing|mainAxisSpacing|crossAxisSpacing|gap)\s*:\s*(\d+(?:\.\d+)?)\b'),
    const ['Spacing', 'Size'],
    false,
  ),
  (RegExp(r'\bsize\s*:\s*(\d+(?:\.\d+)?)\b'), const ['Size'], true),
  (RegExp(r'\bfontSize\s*:\s*(\d+(?:\.\d+)?)\b'), const ['Font', 'Type'], false),
];
