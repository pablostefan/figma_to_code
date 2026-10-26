import 'dart:io';

import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

import 'policy_test.dart' show carteiraConfig;
import 'resolve_test.dart' show instanceNode, screenWith;

/// Ícones como no Acme: constantes estáticas de uma classe (`AcmeIcons.activity`), não um enum.
Future<MappingSet> loadAcmeIcons() async {
  final dir = Directory.systemTemp.createTempSync('f2d_icons');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
  File('${dir.path}/lib/connect/icon.figma.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

class AcmeIconData {
  const AcmeIconData(this.name);
  final String name;
}

abstract class AcmeIcons {
  static const activity = AcmeIconData('activity');
  static const alertCircle = AcmeIconData('alertCircle');
  static const alertTriangle = AcmeIconData('alertTriangle');
  static const String notAnIcon = 'x';
  static final notConst = AcmeIconData('notConst');
  static const _private = AcmeIconData('private');
}

class AcmeIcon extends StatelessWidget {
  const AcmeIcon(this.icon, {super.key});
  final AcmeIconData icon;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@FigmaConnect(key: 'iconset', name: 'Icon', kind: FigmaKind.icon)
Widget icon(FigmaProps f) => AcmeIcon(f.icon('name'));

@FigmaConnect.sketch(key: 'card', name: 'Card', guide: 'Monte com o ícone do Figma.')
typedef Card = AcmeIcon;
''');
  File('${dir.path}/lib/figma_policy.dart').writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';

import 'connect/icon.figma.dart';

const figmaPolicy = FigmaPolicy(icons: IconTable.constants(AcmeIcons, byKey: {'variant7': AcmeIcons.alertCircle}));
''');
  return loadMappings(dir.path, packageConfig: carteiraConfig);
}

void main() {
  late MappingSet maps;
  setUpAll(() async => maps = await loadAcmeIcons());

  Map<String, Object?> swap(String name, {String? variantKey}) => {
    'componentKey': 'iconset',
    if (variantKey != null) 'mainComponentKey': variantKey,
    'componentName': 'Icon',
    'variant': {'name': name},
  };

  String code(Object name) =>
      Resolver(maps).screen(screenWith([instanceNode(key: 'iconset', component: 'Icon', props: {'name': name})]))
          .instances
          .single
          .code;

  test('ícones numa classe de constantes (IconTable.constants): convenção, byKey e ícone que não existe', () {
    expect(code('alert-triangle'), 'AcmeIcon(AcmeIcons.alertTriangle)');
    expect(code(swap('nome-que-nao-existe', variantKey: 'variant7')), 'AcmeIcon(AcmeIcons.alertCircle)');
    // Só constante estática do tipo do DS conta como ícone (não String, não `final`); o primeiro é o provisório.
    expect(
      code('not-an-icon'),
      'AcmeIcon(/* TODO(f2d): ícone "not-an-icon" do Figma não existe em AcmeIcons */ AcmeIcons.activity)',
    );
    expect(code('not-const'), contains('TODO(f2d)'));
  });

  test('ícone nos dados de um sketch sai como constante da classe', () {
    final s = Resolver(
      maps,
    ).screen(screenWith([instanceNode(key: 'card', component: 'Card', props: {'icon': swap('activity')})]));
    expect(componentBrief(s.components.single), contains('- Props do Figma: `{"icon":"AcmeIcons.activity"}`'));
  });
}
