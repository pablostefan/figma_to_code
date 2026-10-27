import 'dart:io';

import 'package:figma2dart/src/api.dart';
import 'package:figma2dart/src/brief.dart';
import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/coverage.dart';
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

// Cores do Acme: a coleção é a marca (`MarcaA/Colors/Surface/primary`, `MarcaB/…`); cada caminho tem a sua classe.
class AcmeSurface {
  final int primary = 1;
}

class AcmeSurfaceBrand {
  final int primary = 2;
}

class AcmeContent {
  final int two = 3;
  final int onBrand = 4;
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
    scopes: {
      'Colors/Surface': TokenSource(AcmeSurface, via: 'context.acme.surface'),
      'Colors/Surface/Brand': TokenSource(AcmeSurfaceBrand, via: 'context.acme.surface.brand'),
      'Colors/Content': TokenSource(AcmeContent, via: 'context.acme.content', names: {'02': 'two', '03': 'three'}),
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

  test('tokens por caminho, em qualquer marca: o caminho mais longo ganha, e os names valem antes do camelCase', () {
    final tokens = maps.policy.tokens!;
    expect(tokens.variable('MarcaA/Colors/Surface/primary'), 'context.acme.surface.primary');
    expect(tokens.variable('MarcaB/Colors/Surface/primary'), 'context.acme.surface.primary');
    expect(tokens.variable('MarcaA/Colors/Surface/Brand/primary'), 'context.acme.surface.brand.primary');
    expect(tokens.variable('MarcaB/Colors/Content/02'), 'context.acme.content.two');
    expect(tokens.variable('MarcaA/Colors/Content/On Brand'), 'context.acme.content.onBrand');
    expect(tokens.variable('MarcaA/Colors/Content/03'), isNull, reason: 'names aponta para um membro que não existe');
    expect(tokens.variable('MarcaA/Colors/Other/primary'), isNull);
    expect(tokens.variable('Spacing/md'), 'context.acmeSpacing.md', reason: 'a coleção vem antes dos caminhos');
  });

  test('cobertura da política: tokens, estilos e ícones sem Dart, agrupados com o que fazer', () {
    final c = policyCoverage({
      'files': {
        'Acme': {
          'tokens': [
            'Spacing/md', 'MarcaA/Colors/Surface/primary', 'MarcaB/Colors/Surface/Brand/primary', //
            'MarcaA/Colors/Feedback/Success/01', 'MarcaA/Colors/Feedback/Success/02', 'MarcaA/Colors/Content/99',
          ],
          'textStyles': ['body/sm', 'title/lg'],
        },
      },
      'pages': {
        'Acme / Icons': {
          'icons': {'k1': 'icon-1', 'variant7': 'outro-nome', 'k9': 'sem-par'},
        },
      },
    }, maps.policy);
    final tokens = c['tokens']! as Json;
    expect((tokens['total'], tokens['withDart']), (6, 3));
    final [noClass, noMember] = (tokens['missing']! as List).cast<Json>();
    expect(noClass['group'], 'MarcaA/Colors/Feedback/Success');
    expect(noClass['count'], 2);
    expect(noClass['fix'], contains('scopes'));
    expect(noMember['group'], 'context.acme.content');
    expect(noMember['examples'], ['MarcaA/Colors/Content/99 → x99']);
    final styles = c['textStyles']! as Json;
    expect(styles['withDart'], 1);
    expect(((styles['missing']! as List).single as Json)['examples'], ['title/lg → titleLg']);
    final icons = c['icons']! as Json;
    expect((icons['total'], icons['withDart']), (3, 2), reason: 'icon-1 pelo camelCase, variant7 pelo byKey');
    expect((icons['missing']! as List).single, {'name': 'sem-par', 'key': 'k9', 'expected': 'semPar'});
  });

  test('ícones do retrato: página de ícones ou set chamado Icon; variant name, variant única ou o componente', () {
    final page = libraryIcons('🧩 Icons', [
      {'key': 'a', 'name': 'Icons/arrow-up', 'variants': <Object>[]},
      {
        'key': 'set',
        'name': 'Glyph',
        'variants': [
          {'id': '1:1', 'key': 'v1', 'props': {'name': 'bell', 'size': '24'}},
          {'id': '1:2', 'props': {'name': 'home', 'size': '24'}},
        ],
      },
    ]);
    expect(page, {'a': 'arrow-up', 'v1': 'bell', '1:2': 'home'});
    expect(libraryIcons('Components', [{'key': 'b', 'name': 'Button Icon', 'variants': <Object>[]}]), isEmpty);
    // Página de um componente com "Icon" no nome não é página de ícones (o Acme tem uma por componente).
    for (final page in ['🔘 Button Icon', 'Icon Button']) {
      expect(libraryIcons(page, [{'key': 'b', 'name': 'Button Icon', 'variants': <Object>[]}]), isEmpty, reason: page);
    }
    expect(libraryIcons('Components', [{'key': 'i', 'name': 'Icon', 'variants': [{'id': '2:1', 'key': 'm', 'props': {'name': 'x'}}]}]), {'m': 'x'});
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
