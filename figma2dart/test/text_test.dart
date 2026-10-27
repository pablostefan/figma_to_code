import 'dart:io';

import 'package:figma2dart/src/brief.dart';
import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/export.dart';
import 'package:figma2dart/src/hints.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:test/test.dart';

import 'commands_test.dart' show mappingsDir, zip;
import 'policy_test.dart' show carteiraConfig;
import 'resolve_test.dart' show instanceNode, screenWith;

/// Como no Acme: o texto é `AcmeText`, e a tipografia vem de um enum no parâmetro `type`; o texto com trechos em
/// estilos diferentes é `AcmeRichText` com um `TextSpan` por trecho (`AcmeTypographyType.title4.styleOf(context)`).
/// O `@FigmaText` e o `@FigmaText.rich` dizem isso uma vez; o brief traz o código de cada texto.
Future<MappingSet> loadAcmeText() async {
  final dir = Directory.systemTemp.createTempSync('f2d_text');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
  File('${dir.path}/lib/figma_policy.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

enum AcmeTypographyType {
  bodySm,
  headingLg,
  title4,
  description,
  descriptionBold;

  TextStyle styleOf(BuildContext context) => const TextStyle();
}

class AcmeRichText extends StatelessWidget {
  const AcmeRichText({required this.text, super.key});
  final InlineSpan text;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class AcmeText extends StatelessWidget {
  const AcmeText(this.text, {required this.type, super.key});
  final String text;
  final AcmeTypographyType type;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class AcmeChip extends StatelessWidget {
  const AcmeChip({required this.label, super.key});
  final String label;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

const figmaPolicy = FigmaPolicy(tokens: TokenTable(textStyles: TokenSource(AcmeTypographyType)));

@FigmaConnect(key: 'chip-ds', name: 'Chip')
Widget chip(FigmaProps f) => AcmeChip(label: f.text('Label'));

@FigmaText.rich()
Widget richText(BuildContext context, FigmaRichTextProps t) => AcmeRichText(
  text: TextSpan(
    children: t.spans(
      (s) => TextSpan(
        text: s.text(),
        style: s.style<AcmeTypographyType>().styleOf(context).copyWith(color: s.color()),
      ),
    ),
  ),
);

@FigmaText()
Widget text(FigmaTextProps t) => AcmeText(
  t.text(),
  type: t.style(),
);
''');
  return loadMappings(dir.path, packageConfig: carteiraConfig);
}

/// As anotações reais do Carteira, com a tipografia trocada por um `AcmeText` com enum (os estilos do export:
/// `body/md`, `body/sm`, `heading/lg`, `heading/md`, `label`).
Future<MappingSet> loadCarteiraWithAcmeText() async {
  final dir = Directory.systemTemp.createTempSync('f2d_carteira_text');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
  Directory('${dir.path}/lib/connect').createSync(recursive: true);
  for (final f in Directory('$mappingsDir/lib/connect').listSync().whereType<File>()) {
    f.copySync('${dir.path}/lib/connect/${f.uri.pathSegments.last}');
  }
  final policy = File('$mappingsDir/lib/figma_policy.dart').readAsStringSync();
  File('${dir.path}/lib/figma_policy.dart').writeAsStringSync(
    "import 'acme_text.figma.dart';\n${policy.replaceFirst('TokenSource(DsTextStyles)', 'TokenSource(AcmeTypographyType)')}",
  );
  File('${dir.path}/lib/acme_text.figma.dart').writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

/// A tipografia do DS.
enum AcmeTypographyType {
  bodyMd,
  bodySm,
  headingLg,
  headingMd,
  label;

  TextStyle styleOf(BuildContext context) => const TextStyle();
}

/// Texto com trechos em estilos diferentes.
class AcmeRichText extends StatelessWidget {
  const AcmeRichText({required this.text, super.key});
  final InlineSpan text;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Todo texto do DS.
class AcmeText extends StatelessWidget {
  const AcmeText(this.text, {required this.type, super.key});
  final String text;
  final AcmeTypographyType type;
  @override
  Widget build(BuildContext context) => const SizedBox();
}

@FigmaText()
Widget text(FigmaTextProps t) => AcmeText(t.text(), type: t.style());

@FigmaText.rich()
Widget richText(BuildContext context, FigmaRichTextProps t) => AcmeRichText(
  text: TextSpan(
    children: t.spans(
      (s) => TextSpan(text: s.text(), style: s.style<AcmeTypographyType>().styleOf(context).copyWith(color: s.color())),
    ),
  ),
);
''');
  return loadMappings(dir.path, packageConfig: carteiraConfig);
}

Json textNode(String characters, {String? style, Json? font, String? bound}) => {
  'id': '7:${characters.hashCode}',
  'type': 'TEXT',
  'name': characters,
  'text': {
    'characters': characters,
    if (style != null) 'style': style,
    if (font != null) 'font': font,
    'color': {'value': '#111111'},
  },
  if (bound != null) 'bindings': {'characters': bound},
};

void main() {
  late MappingSet maps;
  setUpAll(() async => maps = await loadAcmeText());

  test('texto da tela: o código do @FigmaText, com a tipografia pelo enum; o brief proíbe o Text do Flutter', () {
    final s = Resolver(maps).screen(
      screenWith([
        textNode("Olá, it's me", style: 'body/sm'),
        textNode('Solto', font: {'family': 'Inter', 'style': 'Bold', 'size': 14}),
      ]),
    );
    final md = brief(s);
    expect(md, contains(r"texto → `AcmeText('Olá, it\'s me', type: AcmeTypographyType.bodySm)` · #111111"));
    expect(md, contains('`texto → código`: o texto já no widget e na tipografia do DS'));
    // Sem estilo do DS: o lugar do estilo diz isso, para a LLM escolher o mais próximo.
    expect(md, contains("texto → `AcmeText('Solto', type: fonte Inter Bold 14 (sem estilo do DS))`"));
    expect(md, contains('- Não usar `Text`/`TextStyle` do Flutter: texto é o widget do DS (`AcmeText(t.text(), type: t.style())`).'));
  });

  test('texto com trechos em estilos diferentes: AcmeRichText com um TextSpan por trecho, e o check por trecho', () {
    final rich = {
      'id': '7:99',
      'type': 'TEXT',
      'name': 'chance',
      'text': {
        'characters': '72% de chance de Alta',
        'segments': [
          {'characters': '72% ', 'style': 'title4', 'color': {'value': '#111111'}},
          {'characters': 'de chance de ', 'style': 'description', 'color': {'value': '#111111'}},
          {'characters': 'Alta', 'style': 'description/bold', 'colorStyle': 'Feedback/Positive'},
        ],
      },
    };
    final s = Resolver(maps).screen(screenWith([rich]));
    final md = brief(s);
    expect(
      md,
      contains(
        'texto → `AcmeRichText(text: TextSpan(children: ['
        "TextSpan(text: '72% ', style: AcmeTypographyType.title4.styleOf(context).copyWith(color: #111111)), "
        "TextSpan(text: 'de chance de ', style: AcmeTypographyType.description.styleOf(context).copyWith(color: #111111)), "
        "TextSpan(text: 'Alta', style: AcmeTypographyType.descriptionBold.styleOf(context).copyWith(color: Feedback/Positive))"
        ']))`',
      ),
    );
    expect(md, isNot(contains('trechos:'))); // os trechos já estão no código
    // O check procura cada trecho, não a frase inteira (que no código fica partida em TextSpans).
    expect(staticTexts(s.tree), ['72% ', 'de chance de ', 'Alta']);
  });

  test('trecho sem estilo do DS (fonte solta) diz isso no lugar do estilo', () {
    final s = Resolver(maps).screen(
      screenWith([
        {
          'id': '7:98',
          'type': 'TEXT',
          'name': 'misto',
          'text': {
            'characters': 'Oi você',
            'segments': [
              {'characters': 'Oi ', 'style': 'title4'},
              {'characters': 'você'},
            ],
          },
        },
      ]),
    );
    expect(brief(s), contains("TextSpan(text: 'você', style: sem estilo do DS.styleOf(context)"));
  });

  test('função @FigmaText fora do formato: erro que diz o que mudar', () async {
    Future<Object?> load(String fn) async {
      final dir = Directory.systemTemp.createTempSync('f2d_text_bad');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
      File('${dir.path}/lib/figma_policy.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:figma_connect/figma_connect.dart';
import 'package:flutter/widgets.dart';

$fn
''');
      try {
        await loadMappings(dir.path, packageConfig: carteiraConfig);
        return null;
      } on StateError catch (e) {
        return e.message;
      }
    }

    expect(
      await load('''
TextSpan _span(FigmaTextProps s) => TextSpan(text: s.text());

@FigmaText.rich()
Widget rich(FigmaRichTextProps t) => Text.rich(TextSpan(children: t.spans(_span)));
'''),
      contains('`t.spans` precisa de uma função de expressão'),
    );
    expect(
      await load('@FigmaText()\nWidget text(String s) => Text(s);'),
      contains('precisa de um parâmetro FigmaTextProps'),
    );
  });

  test('texto dentro de um componente do DS é atributo dele: o @FigmaText não entra', () {
    final s = Resolver(maps).screen(
      screenWith([
        {
          ...instanceNode(key: 'chip-ds', component: 'Chip', props: {'Label': 'Pix'}),
          'children': [textNode('Pix', style: 'body/sm')],
        },
        textNode('Solto', style: 'body/sm'),
      ]),
    );
    expect(s.instances.single.code, "AcmeChip(label: 'Pix')");
    final md = brief(s);
    expect(md, isNot(contains("AcmeText('Pix'")));
    expect(md, contains("texto → `AcmeText('Solto', type: AcmeTypographyType.bodySm)`"));
  });

  test('texto ligado a uma prop num componente a construir: o parâmetro no lugar do literal', () {
    final ir = screenWith([
      {
        'id': '9:1',
        'type': 'INSTANCE',
        'name': 'Chip',
        'size': {'width': 60, 'height': 24},
        'instance': {
          'componentKey': 'chip',
          'componentName': 'Chip',
          'remote': false,
          'props': {'Label': 'Pix'},
          'exposed': <Object>[],
          'overrides': <Object>[],
        },
      },
    ]);
    ir['components'] = [
      {
        'key': 'chip',
        'name': 'Chip',
        'props': {
          'Label': {'type': 'TEXT', 'default': 'Pix'},
        },
        'variants': [
          {
            'id': 'c1',
            'name': 'Chip',
            'props': <String, Object>{},
            'tree': {
              'id': 'c1',
              'type': 'COMPONENT',
              'name': 'Chip',
              'children': [textNode('Pix', style: 'heading/lg', bound: 'Label')],
            },
          },
        ],
      },
    ];
    final s = Resolver(maps).screen(ir);
    final md = componentBrief(s.components.single, tokens: s.tokens, text: s.text);
    expect(md, contains('texto ← prop `Label` → `AcmeText(label, type: AcmeTypographyType.headingLg)`'));
    expect(md, contains('- Não usar `Text`/`TextStyle` do Flutter'));
  });

  test('export real (Carteira, Transferir): texto solto e componente novo com AcmeText; DS com a string', () async {
    final maps = await loadCarteiraWithAcmeText();
    final s = Resolver(maps).screen(Export.read(zip.path).ir, screen: '03 · Transferir');
    final md = brief(s);
    // Texto solto da tela: o widget e a tipografia do DS.
    expect(md, contains("texto → `AcmeText('Contatos recentes', type: AcmeTypographyType.headingMd)`"));
    // Componente do DS: a string é atributo dele, sem AcmeText.
    final button = s.instances.firstWhere((i) => i.component == 'Button');
    expect(button.code, contains("label: 'Continuar'"));
    expect(button.code, isNot(contains('AcmeText')));
    // Componente novo (a construir): o texto ligado à prop vira o parâmetro, dentro do AcmeText.
    final contact = s.components.firstWhere((c) => c.name == 'ContactItem');
    final cmd = componentBrief(contact, tokens: s.tokens, text: s.text);
    expect(cmd, contains('texto ← prop `name` → `AcmeText(name, type: AcmeTypographyType.'));
    expect(cmd, contains('texto ← prop `detail` → `AcmeText(detail, type: AcmeTypographyType.'));
    expect(cmd, contains('- Não usar `Text`/`TextStyle` do Flutter'));
  });

  test('export real (tela de teste no Figma): texto simples e em trechos, soltos e num componente novo', () async {
    final maps = await loadCarteiraWithAcmeText();
    final ir = Export.read('test/fixtures/texts.ir.json').ir;
    final s = Resolver(maps).screen(ir, screen: '06 · Teste textos');
    final md = brief(s);
    expect(md, contains("texto → `AcmeText('Chance de aprovação', type: AcmeTypographyType.headingMd)`"));
    expect(
      md,
      contains(
        "texto → `AcmeRichText(text: TextSpan(children: [TextSpan(text: '72% ', style: "
        'AcmeTypographyType.headingMd.styleOf(context).copyWith(color: DsColors.textPrimary)), '
        "TextSpan(text: 'de chance de ', style: AcmeTypographyType.bodyMd.styleOf(context)"
        '.copyWith(color: DsColors.textSecondary)), '
        "TextSpan(text: 'Alta', style: AcmeTypographyType.label.styleOf(context).copyWith(color: DsColors.primary))]))`",
      ),
    );
    // Componente do DS na tela: a string é atributo.
    expect(s.instances.firstWhere((i) => i.component == 'Button').code, contains("label: 'Simular empréstimo'"));
    // Componente novo: título ligado à prop no AcmeText; texto fixo em trechos no AcmeRichText; DS com a string.
    final card = componentBrief(s.components.single, tokens: s.tokens, text: s.text);
    expect(card, contains('texto ← prop `title` → `AcmeText(title, type: AcmeTypographyType.headingMd)`'));
    expect(card, contains("TextSpan(text: 'baixo', style: AcmeTypographyType.label.styleOf(context)"));
    expect(card, contains("DsButton( label: 'Ver detalhes'"));
  });
}
