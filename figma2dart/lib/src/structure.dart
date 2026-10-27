import 'dart:convert';

import 'mappings.dart';
import 'names.dart';
import 'resolve.dart';
import 'tokens.dart';

/// Legenda da estrutura, para o brief escrever antes dela. Com [tokens], os tokens já estão em Dart; com [text], os
/// textos trazem o código do widget de texto do DS (`@FigmaText`).
String structureLegend(Tokens? tokens, {bool text = false}) => [
  if (tokens == null)
    'Tokens pelo nome do Figma: use o token do DS correspondente, nunca o valor solto.'
  else ...[
    'Tokens já em Dart (tabela de tokens do DS): use como estão, nunca o valor solto. `(sem Dart, valor)` é token sem',
    'correspondência no código: use o mais próximo do DS e marque `f2d:inferred`.',
    if (tokens.fromTheme)
      'Token do tema (`context.…`) precisa de `BuildContext` (dentro do `build`) e tira o `const` de quem o usa.',
  ],
  'Tamanho `L×A`: número (ou token) = fixo, `HUG` = do tamanho do conteúdo, `FILL` = ocupa o espaço do pai.',
  if (text)
    '`texto → código`: o texto já no widget e na tipografia do DS; use como está.',
].join(' ');

/// A árvore com o código de cada texto (`text.code`) pela função `@FigmaText` do DS. Depois dos tokens em Dart: o
/// estilo e a cor entram já traduzidos. Texto com trechos usa [rich] (`@FigmaText.rich`), um item por trecho; sem ela,
/// ou com o texto ligado a uma prop (os trechos dependem do valor), [template] com "estilo de cada trecho".
Object? withTextCode(Object? node, TextTemplate? template, TextTemplate? rich) => switch (node) {
  final Json n => {
    for (final MapEntry(:key, :value) in n.entries) key: withTextCode(value, template, rich),
    if (n['text'] case final Json text)
      if (_textCode(n, text, template, rich) case final code?) 'text': {...text, 'code': code},
  },
  final List<Object?> list => [for (final item in list) withTextCode(item, template, rich)],
  _ => node,
};

/// Sem estilo do DS (fonte solta) ou com vários estilos, o lugar do estilo diz isso: a LLM usa o mais próximo e
/// marca `f2d:inferred`.
String? _textCode(Json node, Json text, TextTemplate? template, TextTemplate? rich) {
  final bound = (node['bindings'] as Json?)?['characters'] as String?;
  final segments = (text['segments'] as List? ?? const []).cast<Json>();
  // O texto inteiro sem `style` tem trechos; um trecho sem `style` está sem estilo do DS.
  TextValues values(Json t, String characters, {String noStyle = 'estilo de cada trecho'}) => (
    text: characters,
    style: t['style'] as String? ?? noStyle,
    color: _color(t) ?? 'cor do estilo',
  );
  if (rich != null && segments.isNotEmpty && bound == null) {
    return oneLine(
      rich.render(
        values(text, dartString(text['characters'] as String? ?? '')),
        spans: [
          for (final s in segments)
            values(s, dartString(s['characters'] as String? ?? ''), noStyle: 'sem estilo do DS'),
        ],
      ),
    );
  }
  if (template == null) return null;
  final font = text['font'] as Json?;
  final v = values(text, bound == null ? dartString(text['characters'] as String? ?? '') : identifier(bound));
  return oneLine(
    template.render((
      text: v.text,
      style: font == null || text['style'] != null
          ? v.style
          : 'fonte ${font['family']} ${font['style']} ${_num(font['size'])} (sem estilo do DS)',
      color: v.color,
    )),
  );
}

/// Código de várias linhas numa linha só, sem a vírgula do fim: `AcmeText(\n  'x',\n)` → `AcmeText('x')`.
String oneLine(String code) => code
    .replaceAll(RegExp(r'\(\s*\n\s*'), '(')
    .replaceAll(RegExp(r',?\s*\n\s*\)'), ')')
    .replaceAll(RegExp(r'\s*\n\s*'), ' ');

/// O código já tem cada trecho (`@FigmaText.rich`): a lista de trechos não se repete.
bool _spansIn(String? code, List<Object?> segments) =>
    code != null && segments.cast<Json>().every((s) => code.contains(dartString(s['characters'] as String? ?? '')));

String? _color(Json text) => text['colorStyle'] as String? ?? (text['color'] == null ? null : _value(text['color']));

/// Uma camada da estrutura: [path] é o caminho a partir da raiz (`.` é a raiz; compara variantes) e [parts] o que
/// ela tem, já escrito.
typedef StructureLine = ({int depth, String path, String name, List<String> parts});

/// Uma linha por nó: layout e estilo pelos tokens, textos com a prop ligada, instâncias do DS com o código pronto.
/// [brief] dá o link para o brief de construção de um componente local. Com [inline] falso, instância do DS aponta
/// para o código dela na seção Componentes do brief em vez de repetir o código. [exposed]: caminhos das instâncias
/// expostas (os valores vêm de cada uso).
void writeStructure(
  StringBuffer out,
  Json node,
  Map<String, ResolvedInstance> resolved,
  String Function(ResolvedInstance) brief, {
  bool inline = true,
  Set<String> exposed = const {},
}) {
  for (final l in structureLines(node, resolved, brief, inline: inline, exposed: exposed)) {
    out.writeln('${'  ' * l.depth}- `${l.name}`: ${l.parts.join(' · ')}');
  }
}

List<StructureLine> structureLines(
  Json node,
  Map<String, ResolvedInstance> resolved,
  String Function(ResolvedInstance) brief, {
  bool inline = true,
  Set<String> exposed = const {},
  int depth = 0,
  String path = '.',
}) {
  if (node['visible'] == false) return const [];
  final name = '${node['name']}';
  StructureLine line(List<String> parts) => (depth: depth, path: path, name: name, parts: parts);

  if (resolved[node['id']] case final i?) {
    // Os valores desta instância, onde a LLM está olhando (o brief do componente repete por instância).
    final values = [
      if (i.figma?['props'] case final Json props when props.isNotEmpty) 'props ${jsonEncode(props)}',
      if (i.figma?['exposed'] case final List<Object?> list when list.isNotEmpty)
        'expostas ${jsonEncode({for (final e in list.cast<Json>()) e['path']: e['props']})}',
    ];
    final parts = switch (i.status) {
      'placeholder' => ['componente local **${i.component}** → [brief](${brief(i)})', ...values],
      'gap' => ['${i.component} do DS **sem mapeamento**${i.error == null ? '' : ' (${i.error})'}'],
      'sketch' => ['DS **${i.component}** a montar → [brief](${brief(i)})', ...values],
      'local' => ['widget do app **${i.mapping!.widget!.name}** a montar → [brief](${brief(i)})', ...values],
      _ when !inline => ['DS **${i.component}** (código em Componentes, ${i.id})'],
      _ => [
        'DS `${i.code.replaceAll(RegExp(r'\n\s*'), ' ')}`', // só as quebras: espaço de texto fica
        for (final o in i.overrides)
          if (o['values'] case final Json values) 'override `${o['node']}`: ${_override(values)}',
      ],
    };
    // O tamanho da instância no Figma: o mapeamento pode não ler (ícone redimensionado para 20 com padrão 24).
    if (_size(node, root: false) case final size?) parts.add(size);
    if (_rotation(node) case final rotation?) parts.add(rotation);
    if (exposed.contains(path)) parts.add('**exposta**: os valores mudam em cada uso (veja "Usos na tela")');
    return [line(parts)];
  }
  // Instância que o resolvedor pulou: só do Figma (`FigmaPolicy.ignored` ou prefixo `_`/`.`).
  if (node['instance'] != null) {
    return [
      line(const ['**não implementar** (só do Figma)']),
    ];
  }
  // Vetor solto (ilustração desenhada na tela): o export não traz o arquivo; fica um placeholder do tamanho do nó.
  if (_vectorOnly(node)) {
    return [
      line(['vetor → `${_todo(node, 'vetor')}`']),
    ];
  }

  final parts = <String>[...?_text(node), if (node['text'] == null) node['type'] as String];
  if (node['layout'] case final Json layout) parts.add(_layout(layout));
  if (node['style'] case final Json style) parts.addAll(_style(node, style));
  if (_size(node, root: depth == 0) case final size?) parts.add(size);
  if (_rotation(node) case final rotation?) parts.add(rotation);
  if (node['position'] case {'x': final x, 'y': final y}) parts.add('posição absoluta ${_num(x)},${_num(y)}');
  if ((node['bindings'] as Json?)?['visible'] case final visible?) parts.add('visível ← prop `$visible`');
  return [
    line(parts),
    for (final child in (node['children'] as List? ?? const []).cast<Json>())
      ...structureLines(
        child,
        resolved,
        brief,
        inline: inline,
        exposed: exposed,
        depth: depth + 1,
        path: path == '.' ? '${child['name']}' : '$path/${child['name']}',
      ),
  ];
}

List<String>? _text(Json node) {
  final text = node['text'] as Json?;
  if (text == null) return null;
  final bound = (node['bindings'] as Json?)?['characters'];
  final font = text['font'] as Json?;
  final resize = switch (text['autoResize']) {
    'HEIGHT' => 'quebra linha (largura fixa)',
    'NONE' => 'caixa fixa',
    'TRUNCATE' => 'corta na caixa',
    _ => null,
  };
  final code = text['code'] as String?;
  return [
    if (code != null)
      'texto ${bound == null ? '' : '← prop `$bound` '}→ `$code`'
    else
      'texto ${bound == null ? jsonEncode(text['characters']) : '← prop `$bound`'}',
    // O que já está no código não se repete.
    if ([
          text['style'] ?? (font == null ? null : 'fonte ${font['family']} ${font['style']} ${_num(font['size'])}'),
          _color(text),
        ].whereType<String>().where((part) => code == null || !code.contains(part)).join(' ').nullIfEmpty
        case final styleAndColor?)
      styleAndColor,
    if (text['align'] case final String align when align != 'LEFT') 'alinhado $align',
    if (text['maxLines'] case final int lines) 'máx $lines ${lines == 1 ? 'linha' : 'linhas'}',
    if (text['truncation'] == 'ENDING') 'reticências',
    if (resize != null) resize,
    if (text['segments'] case final List<Object?> segments when segments.isNotEmpty && !_spansIn(code, segments))
      'trechos: ${[
        for (final s in segments.cast<Json>()) [jsonEncode(s['characters']), s['style'], s['colorStyle'] ?? (s['color'] == null ? null : _value(s['color']))].whereType<Object>().join(' '),
      ].join(', ')}',
  ];
}

String _layout(Json layout) {
  final gap = layout['gap'];
  final align = layout['align'] as Json;
  return [
    layout['direction'],
    if (layout['grid'] case final Json grid)
      'grade ${grid['rows']}×${grid['columns']}, gap linhas ${_value(grid['rowGap'])} colunas ${_value(grid['columnGap'])}'
    else if (gap == 'auto')
      'espaço entre os filhos (space-between)'
    else if (gap != null && _value(gap) != '0')
      'gap ${_value(gap)}',
    if (layout['wrap'] == true)
      'quebra linha${layout['counterGap'] == null ? '' : ' (gap entre linhas ${_value(layout['counterGap'])})'}',
    if (_padding(layout['padding'] as Json) case final padding?) padding,
    'align ${align['main']}/${align['cross']}',
  ].join(' ');
}

/// Padding com o lado escrito: um valor, vertical/horizontal ou os quatro.
String? _padding(Json p) {
  final [top, right, bottom, left] = [
    for (final side in ['top', 'right', 'bottom', 'left']) _value(p[side]),
  ];
  if (top == right && right == bottom && bottom == left) return top == '0' ? null : 'padding $top';
  if (top == bottom && left == right) return 'padding vertical $top, horizontal $left';
  return 'padding cima $top, direita $right, baixo $bottom, esquerda $left';
}

List<String> _style(Json node, Json style) => [
  if (style['fillStyle'] ?? _paints(style['fills']) case final fill?) 'fill $fill',
  if ((style['fills'] as List? ?? const []).any((p) => (p as Json)['type'] == 'IMAGE'))
    'imagem → `${_todo(node, 'imagem')}` (fundo; os filhos vão por cima)',
  if (style['strokeStyle'] ?? _paints(style['strokes']) case final stroke?)
    [
      'stroke $stroke',
      if (style['strokeWeight'] case final weight?) _sides(weight),
      if (style['strokeAlign'] case final String align when align != 'INSIDE') align,
    ].join(' '),
  if (style['radius'] case final radius?) 'radius ${_sides(radius)}',
  if (style['opacity'] case final num opacity when opacity < 1) 'opacidade ${_percent(opacity)}',
  for (final e in (style['effects'] as List? ?? const []).cast<Json>()) _effect(e),
  if (style['clipsContent'] == true) 'recorta o conteúdo',
];

/// Valor único ou por lado/canto, com o nome de cada um quando diferem.
String _sides(Object value) {
  if (value is! Map || value.values.any((v) => v is! Map)) return _value(value);
  final values = {for (final MapEntry(:key, :value) in value.entries) key: _value(value)};
  if (values.values.toSet().length == 1) return values.values.first;
  // Borda só embaixo, raio só em cima…: o lado zerado fica implícito.
  final set = values.entries.where((e) => e.value != '0');
  return '${set.map((e) => '${_sideNames[e.key] ?? e.key} ${e.value}').join(', ')}'
      '${set.length < values.length ? ' (outros 0)' : ''}';
}

const _sideNames = {
  'top': 'cima',
  'right': 'direita',
  'bottom': 'baixo',
  'left': 'esquerda',
  'topLeft': 'cima-esq',
  'topRight': 'cima-dir',
  'bottomRight': 'baixo-dir',
  'bottomLeft': 'baixo-esq',
};

String _effect(Json e) {
  if (e['style'] case final String style) return 'efeito $style';
  final offset = e['offset'] as Json?;
  final shadow = [
    if (e['color'] case final color?) color,
    if (offset != null) 'x ${_num(offset['x'])} y ${_num(offset['y'])}',
    if (e['radius'] != null) 'blur ${_num(e['radius'])}',
    if (e['spread'] case final num spread when spread != 0) 'spread ${_num(spread)}',
  ].join(' ');
  return switch (e['type']) {
    'DROP_SHADOW' => 'sombra $shadow',
    'INNER_SHADOW' => 'sombra interna $shadow',
    'LAYER_BLUR' => 'desfoque ${_num(e['radius'])}',
    'BACKGROUND_BLUR' => 'desfoque do fundo ${_num(e['radius'])}',
    final type => '$type $shadow',
  };
}

/// Tamanho `L×A`: número (ou token) no eixo fixo, `HUG`/`FILL` nos outros. A raiz de um componente não leva número:
/// a largura dela vem de quem usa. Nó fora do auto layout (sem `sizing`) leva o tamanho.
/// Rotação do Figma (graus, anti-horário). Em Flutter: `Transform.rotate(angle: -graus * pi / 180)`.
String? _rotation(Json node) => switch (node['rotation']) {
  final num r when r.abs() == 180 => '**girado 180°**',
  final num r => '**girado ${_num(r.abs())}° ${r > 0 ? 'anti-horário' : 'horário'}**',
  _ => null,
};

String? _size(Json node, {required bool root}) {
  final size = node['size'] as Json? ?? const {};
  final tokens = node['sizeTokens'] as Json? ?? const {};
  String fixed(String dim) => '${tokens[dim] ?? _num(size[dim])}';
  final sizing = node['sizing'] as Json?;
  final text = switch (sizing) {
    {'horizontal': final String h, 'vertical': final String v} =>
      '${h == 'FIXED' && !root ? fixed('width') : h}×${v == 'FIXED' && !root ? fixed('height') : v}',
    _ when root || size.isEmpty => null,
    _ => '${fixed('width')}×${fixed('height')}',
  };
  final limits = node['limits'] as Json? ?? const {};
  return [
    if (text != null) text,
    for (final MapEntry(:key, :value) in limits.entries)
      '${key.startsWith('min') ? 'mín' : 'máx'} ${key.endsWith('Width') ? 'L' : 'A'} ${_value(value)}',
  ].join(' ').nullIfEmpty;
}

/// Override de instância legível: o que mudou e para quê.
String _override(Json values) => [
  for (final MapEntry(:key, :value) in values.entries)
    switch (key) {
      'fills' => 'fill ${_paints(value)}',
      'strokes' => 'cor do traço ${_paints(value)}',
      'characters' => 'texto ${jsonEncode(value)}',
      'visible' => value == true ? 'visível' : 'oculto',
      'opacity' => 'opacidade ${_percent(value as num)}',
      'component' => 'troca para ${(value as Json)['componentName']}',
      _ => '$key ${jsonEncode(value)}',
    },
].join(', ');

const _vectorTypes = {'VECTOR', 'BOOLEAN_OPERATION', 'STAR', 'POLYGON'};

/// Nó só de vetores: um vetor, ou um grupo/frame cujos filhos são todos vetores.
bool _vectorOnly(Json node) {
  if (_vectorTypes.contains(node['type'])) return true;
  final children = (node['children'] as List? ?? const []).cast<Json>();
  return const {'GROUP', 'FRAME', 'COMPONENT'}.contains(node['type']) &&
      children.isNotEmpty &&
      children.every(_vectorOnly);
}

/// Placeholder do tamanho do nó com o aviso para o dev: o export ainda não traz imagens e vetores como arquivo.
String _todo(Json node, String what) {
  final size = node['size'] as Json? ?? const {};
  return '/* TODO(f2d): $what do Figma "${node['name']}" (${node['id']}), asset ainda não exportado */ '
      'const SizedBox(width: ${size['width']}, height: ${size['height']}, child: Placeholder())';
}

String? _paints(Object? paints) {
  final list = [
    for (final p in (paints as List? ?? const []).cast<Json>())
      switch (p['type']) {
        'SOLID' => [_value(p['color']), if (p['opacity'] case final num o when o < 1) _percent(o)].join(' '),
        'GRADIENT' =>
          'gradiente ${p['kind']} ${[for (final s in (p['stops'] as List).cast<Json>()) _value(s['color'])].join(' → ')}',
        final type => '$type',
      },
  ];
  return list.isEmpty ? null : list.join(', ');
}

/// `{value, token}` → o token, ou o valor quando não há token. Valor por lado ou canto vira `a/b/c/d`.
String _value(Object? v) => switch (v) {
  {'token': final String token} => token,
  {'value': final value} => _num(value),
  Json m when m.values.every((x) => x is Map) => m.values.map(_value).join('/'), // por lado ou canto
  _ => '$v',
};

/// Número sem `.0` à toa.
String _num(Object? v) => v is double && v == v.roundToDouble() ? '${v.toInt()}' : '$v';

String _percent(num v) => '${_num((v * 100).round())}%';

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
