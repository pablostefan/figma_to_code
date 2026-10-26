import 'dart:io';

import 'package:figma2dart/src/api.dart';
import 'package:figma2dart/src/brief.dart';
import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

import 'resolve_test.dart' show instanceNode, screenWith;

// Usa o package_config do carteira_ds_figma para resolver flutter e figma_connect no pacote temporário.
const carteiraConfig = '../../design_system/carteira_ds_figma/.dart_tool/package_config.json';

/// Pacote de mapeamentos com o que o Carteira não usa: política com `ignored`, regras por tipo e `byKey`,
/// `figmaNotes`, enum de ícones grande e um sketch que recebe ícone.
Future<MappingSet> loadPolicyPackage() async {
  final dir = Directory.systemTemp.createTempSync('f2d_policy');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
  final values = [for (var i = 0; i < 40; i++) 'icon$i'];
  File('${dir.path}/lib/connect/w.figma.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

enum Big { ${values.join(', ')} }

// Tokens como no Acme: pelo tema (`context.acmeSpacing.md`); o nome do Figma no doc ou o camelCase dele.
class AcmeSpacing {
  /// `2xs` = 2
  final double xxs = 2;
  final double md = 12;
}

class AcmeColors {
  /// `text/primary`
  final int textPrimary = 1;
}

abstract final class AcmeText {
  /// `body/sm`
  static const int bodySm = 1;
}

class W extends StatelessWidget {
  const W({required this.icon, super.key});
  final Big icon;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@FigmaConnect(key: 'iconset', name: 'Icon', kind: FigmaKind.icon)
Widget icon(FigmaProps f) => W(icon: f.icon('name'));

@FigmaConnect(
  key: 'w2',
  name: 'W2',
  figmaNotes: {
    'state': FigmaNote.derive('Vem do erro da validação.'),
    'Currency': FigmaNote.map({'Global': null, 'BRL': 'brl'}, hint: 'Global = sem filtro'),
    'Collapse': FigmaNote.ignore('Só visual'),
  },
)
Widget w2(FigmaProps f) => W(icon: f.icon('icon'));

@FigmaConnect.sketch(key: 'w3', name: 'W3', guide: 'Monte com o ícone do Figma.')
typedef W3 = W;
''');
  File('${dir.path}/lib/figma_policy.dart').writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';

import 'connect/w.figma.dart';

const figmaPolicy = FigmaPolicy(
  kinds: {FigmaKind.component: KindPolicy(devNotes: [DevNote.must('Regra do tipo.')])},
  icons: IconTable(values: Big.values, byKey: {'variant7': Big.icon7}),
  tokens: TokenTable(
    collections: {
      'Spacing': TokenSource(AcmeSpacing, via: 'context.acmeSpacing'),
      'Color': TokenSource(AcmeColors, via: 'context.acmeColors'),
    },
    textStyles: TokenSource(AcmeText),
  ),
  ignored: {'handoff': 'Anotação de handoff'},
);
''');
  return loadMappings(dir.path, packageConfig: carteiraConfig);
}

void main() {
  late MappingSet maps;
  setUpAll(() async => maps = await loadPolicyPackage());

  Json swap(String name, {String? variantKey}) => {
    'componentKey': 'iconset',
    if (variantKey != null) 'mainComponentKey': variantKey,
    'componentName': 'Icon',
    'variant': {'name': name},
  };

  test('política: ignorados (key e prefixo) saem da tela e viram "Não implementar"', () {
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(key: 'handoff', component: 'Nota', props: {}),
        instanceNode(key: 'outra', component: '_Base/Shape', props: {}),
        instanceNode(key: 'w2', component: 'W2', props: {'icon': swap('icon3')}),
      ]),
    );
    expect(s.instances.map((i) => i.component), ['W2']);
    final md = brief(s);
    expect(md, contains('- Não implementar `Nota` (Nota): Anotação de handoff.'));
    expect(md, contains('- Não implementar `_Base/Shape` (_Base/Shape): componente só do Figma (prefixo `_`).'));
    expect(md, contains('- `Nota`: **não implementar** (só do Figma)')); // também na estrutura
  });

  test('regras do tipo, figmaNotes e byKey chegam ao brief', () {
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(
          key: 'w2',
          component: 'W2',
          props: {'icon': swap('nome-que-nao-existe', variantKey: 'variant7')},
        ),
      ]),
    );
    expect(s.instances.single.code, 'W(icon: Big.icon7)'); // byKey vence a convenção
    final md = brief(s);
    expect(md, contains('- [obrigatório] Regra do tipo.'));
    expect(md, contains('- Figma `state`: Vem do erro da validação.'));
    expect(md, contains("- Figma `Currency`: Global → null, BRL → 'brl' — Global = sem filtro"));
    expect(md, isNot(contains('Collapse')));
  });

  test('tokens do tema já saem em Dart na estrutura; sem correspondência, o nome e o valor', () {
    Json v(Object value, String token) => {'value': value, 'token': token};
    final ir = screenWith([
      {
        'id': '2:1',
        'type': 'TEXT',
        'name': 'title',
        'text': {'characters': 'Oi', 'style': 'body/sm', 'color': v('#111', 'Color/text/primary')},
      },
    ]);
    ((((ir['screens'] as List).single as Json)['states'] as List).single as Json)['tree'] = {
      ...(((((ir['screens'] as List).single as Json)['states'] as List).single as Json)['tree'] as Json),
      'layout': {
        'direction': 'VERTICAL',
        'gap': v(2, 'Spacing/2xs'),
        'padding': {
          'top': v(12, 'Spacing/md'),
          'right': v(48, 'Spacing/huge'),
          'bottom': v(12, 'Spacing/md'),
          'left': v(48, 'Spacing/huge'),
        },
        'align': {'main': 'MIN', 'cross': 'MIN'},
      },
    };
    final md = brief(Resolver(maps).screen(ir));
    expect(
      md,
      contains(
        'VERTICAL gap context.acmeSpacing.xxs padding vertical context.acmeSpacing.md, '
        'horizontal Spacing/huge (sem Dart, 48)',
      ),
    );
    expect(md, contains('texto "Oi" · AcmeText.bodySm context.acmeColors.textPrimary'));
    expect(md, contains('precisa de `BuildContext`'));
  });

  test('enum grande entra cortado na API, e o ícone do sketch chega resolvido', () {
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(key: 'w3', component: 'W3', props: {'icon': swap('icon12')}),
      ]),
    );
    final w3 = maps.components.firstWhere((m) => m.name == 'W3');
    expect(
      widgetApi(w3.widget!),
      contains('enum Big { icon0, icon1, icon2, icon3, icon4, icon5, icon6, icon7, icon8, icon9, … } // 40 valores'),
    );
    expect(componentBrief(s.components.single), contains('- Props do Figma: `{"icon":"Big.icon12"}`'));
  });
}
