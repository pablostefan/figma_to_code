import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

import 'resolve_test.dart' show instanceNode, screenWith;

Json v(Object value, [String? token]) => {'value': value, if (token != null) 'token': token};

/// Variant de um botão local: o que muda entre elas é o gap, o estilo do texto e, na `lg`, um ícone a mais.
Json variant(String name, {required String gap, required String textStyle, bool icon = false}) => {
  'id': 'v-$name',
  'name': 'size=$name',
  'props': {'size': name},
  'tree': {
    'id': 'r-$name',
    'type': 'COMPONENT',
    'name': 'Card',
    'size': {'width': 200, 'height': 48},
    'sizing': {'horizontal': 'FIXED', 'vertical': 'HUG'},
    'limits': {'maxWidth': v(320)},
    'layout': {
      'direction': 'HORIZONTAL',
      'gap': v(8, gap),
      'padding': {'top': v(12), 'right': v(16), 'bottom': v(12), 'left': v(16)},
      'align': {'main': 'MIN', 'cross': 'CENTER'},
      'wrap': false,
    },
    'style': {
      'radius': {'topLeft': v(12), 'topRight': v(12), 'bottomRight': v(0), 'bottomLeft': v(0)},
      'effects': [
        {
          'type': 'DROP_SHADOW',
          'color': '#0000001A',
          'offset': {'x': 0, 'y': 2},
          'radius': 8,
          'spread': 0,
        },
      ],
      'opacity': 0.9,
      'clipsContent': true,
    },
    'children': [
      {
        'id': 't-$name',
        'type': 'TEXT',
        'name': 'value',
        'size': {'width': 60, 'height': 20},
        'sizing': {'horizontal': 'HUG', 'vertical': 'HUG'},
        'text': {
          'characters': r'R$ 120',
          'style': textStyle,
          'align': 'RIGHT',
          'segments': [
            {'characters': r'R$ ', 'style': 'body/sm'},
            {'characters': '120', 'style': textStyle},
          ],
        },
      },
      {
        'id': 'n-$name',
        'type': 'TEXT',
        'name': 'note',
        'sizing': {'horizontal': 'FILL', 'vertical': 'HUG'},
        'text': {
          'characters': 'Obs',
          'style': 'body/sm',
          'maxLines': 1,
          'truncation': 'ENDING',
          'autoResize': 'HEIGHT',
        },
      },
      {
        'id': 'd-$name',
        'type': 'RECTANGLE',
        'name': 'divider',
        'size': {'width': 200, 'height': 1},
        'rotation': -90,
        'sizing': {'horizontal': 'FILL', 'vertical': 'FIXED'},
      },
      {
        'id': 'b-$name',
        'type': 'FRAME',
        'name': 'badge',
        'size': {'width': 8, 'height': 8},
        'rotation': 180,
        'position': {'x': 190, 'y': 2},
      },
      if (icon)
        {
          'id': 'i-$name',
          'type': 'FRAME',
          'name': 'icon',
          'size': {'width': 20, 'height': 20},
          'sizeTokens': {'width': 'Size/icon/sm', 'height': 'Size/icon/sm'},
          'sizing': {'horizontal': 'FIXED', 'vertical': 'FIXED'},
        },
    ],
  },
  if (name == 'md') 'svg': '<svg/>',
};

void main() {
  test('estrutura completa e só o que muda em cada variante', () {
    final ir = {
      ...screenWith([
        instanceNode(key: 'card', component: 'Card', props: {'size': 'md'}, remote: false),
      ]),
      'components': [
        {
          'id': 'c',
          'key': 'card',
          'name': 'Card',
          'role': 'dependency',
          'props': {
            'size': {
              'type': 'VARIANT',
              'default': 'md',
              'options': ['md', 'sm', 'lg'],
            },
          },
          'variants': [
            variant('md', gap: 'Spacing/sm', textStyle: 'body/md'),
            variant('sm', gap: 'Spacing/xs', textStyle: 'body/sm'),
            variant('lg', gap: 'Spacing/sm', textStyle: 'body/md', icon: true),
          ],
        },
      ],
    };
    final md = componentBrief(Resolver(MappingSet(const [])).screen(ir).components.single);

    // Uma árvore só, com o que o IR tem.
    expect(md, contains('## Estrutura (base: `size=md`)'));
    expect(md, isNot(contains('## Estrutura: ')));
    expect(
      md,
      contains(
        '- `Card`: COMPONENT · HORIZONTAL gap Spacing/sm padding vertical 12, horizontal 16 align MIN/CENTER · '
        'radius cima-esq 12, cima-dir 12 (outros 0) · opacidade 90% · sombra #0000001A x 0 y 2 blur 8 · '
        'recorta o conteúdo · FIXED×HUG máx L 320',
      ),
    );
    expect(
      md,
      contains(
        r'- `value`: texto "R$ 120" · body/md · alinhado RIGHT · trechos: "R$ " body/sm, "120" body/md · HUG×HUG',
      ),
    );
    expect(md, contains('- `divider`: RECTANGLE · FILL×1 · **girado 90° horário**'));
    expect(md, contains('texto "Obs" · body/sm · máx 1 linha · reticências · quebra linha (largura fixa) · FILL×HUG'));
    expect(md, contains('- `badge`: FRAME · 8×8 · **girado 180°** · posição absoluta 190,2'));

    // As outras variantes: só a diferença.
    expect(md, contains('## O que muda em cada variante'));
    expect(md, contains('- `size=sm`:\n  - `.`: HORIZONTAL gap Spacing/sm'));
    expect(md, contains('→ HORIZONTAL gap Spacing/xs'));
    expect(md, contains('  - `value`: body/md · trechos: "R\$ " body/sm, "120" body/md → body/sm · trechos'));
    expect(md, contains('- `size=lg`:\n  - `icon`: camada nova — FRAME · Size/icon/sm×Size/icon/sm'));
    expect(md, contains('SVG de `size=md` (do Figma): `size_md.svg`'));
  });
}
