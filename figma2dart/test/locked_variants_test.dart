import 'dart:io';

import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

import 'policy_test.dart' show carteiraConfig;
import 'resolve_test.dart' show instanceNode, screenWith;

/// Como no Acme: `Button Icon` (público) só tem o tamanho; dentro, exposta como `✏️ Icon Button`, uma base travada por
/// tamanho (`.Icon Button / Large`, `.Icon Button / Medium`), cada uma com a sua key e as mesmas props. Uma anotação
/// só, na key do público, lê as props da base exposta pelo nome. Nomes de prop com emoji, como no Figma.
Future<MappingSet> loadLockedVariants() async {
  final dir = Directory.systemTemp.createTempSync('f2d_locked');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
  File('${dir.path}/lib/connect/icon_button.figma.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

enum AcmeIconName { home, bell }

enum AcmeIconButtonSize { medium, large }

enum AcmeIconButtonType { primary, secondary }

class AcmeIconButton extends StatelessWidget {
  const AcmeIconButton({
    required this.icon,
    this.size = AcmeIconButtonSize.large,
    this.type = AcmeIconButtonType.primary,
    this.notification = false,
    this.onPressed,
    super.key,
  });
  final AcmeIconName icon;
  final AcmeIconButtonSize size;
  final AcmeIconButtonType type;
  final bool notification;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@FigmaConnect(key: 'button-icon', name: 'Button Icon')
Widget buttonIcon(FigmaProps f) => AcmeIconButton(
  icon: f.icon('🔄 Icon'),
  size: f.variant('👉 Size', {'Large': AcmeIconButtonSize.large, 'Medium': AcmeIconButtonSize.medium}),
  type: f.variant('✏️ Type', {'Primary': AcmeIconButtonType.primary, 'Secondary': AcmeIconButtonType.secondary}),
  notification: f.boolean('🔔 Notification'),
  onPressed: f.variant('🔒 Disabled', {'True': null, 'False': f.guided('onPressed', guide: 'Ação do botão.', or: () {})}),
);

// Base com anotação própria (para quando ela aparece solta na tela).
@FigmaConnect(key: 'icon-button-medium', name: '.Icon Button / Medium')
Widget iconButtonMedium(FigmaProps f) => AcmeIconButton(icon: f.icon('🔄 Icon'), size: AcmeIconButtonSize.medium);
''');
  File('${dir.path}/lib/figma_policy.dart').writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';

import 'connect/icon_button.figma.dart';

const figmaPolicy = FigmaPolicy(icons: IconTable(values: AcmeIconName.values));
''');
  return loadMappings(dir.path, packageConfig: carteiraConfig);
}

void main() {
  late MappingSet maps;
  setUpAll(() async => maps = await loadLockedVariants());

  Json base({String icon = 'bell', String type = 'Secondary', String disabled = 'False', bool notification = true}) => {
    '🔄 Icon': {
      'componentKey': 'iconset',
      'componentName': 'Icon',
      'variant': {'name': icon},
    },
    '🔔 Notification': notification,
    '✏️ Type': type,
    '🔒 Disabled': disabled,
  };

  Json buttonIcon(String size, List<(String, String, Json)> exposed) {
    final node = instanceNode(key: 'button-icon', component: 'Button Icon', props: {'👉 Size': size});
    (node['instance'] as Json)['exposed'] = [
      for (final (path, key, props) in exposed)
        {
          'path': path,
          'componentKey': key,
          'componentName': '.Icon Button / $size',
          'props': props,
          'exposed': <Object>[],
        },
    ];
    return node;
  }

  test('uma anotação na key do público lê as props da base exposta, qualquer que seja a base (tamanho)', () {
    final s = Resolver(maps).screen(
      screenWith([
        buttonIcon('Large', [('✏️ Icon Button', 'icon-button-large', base())]),
        buttonIcon('Medium', [
          ('✏️ Icon Button', 'icon-button-medium', base(icon: 'home', type: 'Primary', disabled: 'True')),
        ]),
      ]),
    );
    final [large, medium] = s.instances.map((i) => i.code.replaceAll(RegExp(r'\s+'), ' ')).toList();
    expect(large, contains('icon: AcmeIconName.bell'));
    expect(large, contains('size: AcmeIconButtonSize.large'));
    expect(large, contains('type: AcmeIconButtonType.secondary'));
    expect(large, contains('notification: true'));
    expect(large, contains('/* f2d:guided G1 onPressed */'));
    expect(medium, contains('size: AcmeIconButtonSize.medium'));
    expect(medium, contains('icon: AcmeIconName.home'));
    expect(medium, contains('onPressed: null'));
  });

  test('prop em duas expostas não é escolhida por acaso: vira lacuna pedindo f.nested', () {
    final s = Resolver(maps).screen(
      screenWith([
        buttonIcon('Large', [('a', 'icon-button-large', base()), ('b', 'icon-button-large', base())]),
      ]),
    );
    expect(s.instances.single.code, contains('f2d:gap'));
    expect(s.instances.single.code, contains('está em a e b; leia com f.nested'));
  });

  test('base com `.` no nome e anotação própria entra na tela; sem anotação, continua só do Figma', () {
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(key: 'icon-button-medium', component: '.Icon Button / Medium', props: base()),
        instanceNode(key: 'outra', component: '.Base / Shape', props: {}),
      ]),
    );
    expect(s.instances.single.code, contains('size: AcmeIconButtonSize.medium'));
    expect(s.ignored.single['component'], '.Base / Shape');
  });
}
