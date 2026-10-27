import 'dart:io';

import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/hints.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/tokens.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

import 'dart:convert';

import 'commands_test.dart' show mappingsDir, tempApp, zip;
import 'resolve_test.dart' show instanceNode, screenWith, statementKey;

void main() {
  const tokens = {
    '12': [
      {'code': 'DsSpacing.md', 'token': 'Spacing/md'},
      {'code': 'DsRadius.md', 'token': 'Radius/md'},
    ],
    '24': [
      {'code': 'DsSize.icon', 'token': 'Size/icon'},
    ],
    '#64748B': [
      {'code': 'DsPrimitives.gray500', 'token': 'Primitives/gray/500'},
      {'code': 'DsColors.textSecondary', 'token': 'Color/text/secondary'},
    ],
  };

  List<String> messages(String source, {Json? expect}) => [
    for (final h in hintsFor('w.dart', source, expect: expect, tokens: tokens)) '${h['line'] ?? '-'} ${h['message']}',
  ];

  test('valor solto: a dica traz o token do mesmo valor, pelo contexto; f2d:inferred cala a linha', () {
    expect(
      messages('''
padding: const EdgeInsets.all(12),
borderRadius: BorderRadius.circular(12),
color: const Color(0xFF64748B),
color: Colors.red,
SizedBox(height: 1), // f2d:inferred — divisor de 1px, sem token
const SizedBox(width: 20),
'''),
      [
        '1 `12` solto em `EdgeInsets.all(12)` → use `DsSpacing.md`',
        '2 `12` solto em `BorderRadius.circular(12)` → use `DsRadius.md`',
        '3 cor solta `Color(0xFF64748B)` → use `DsColors.textSecondary` ou `DsPrimitives.gray500`',
        '4 cor do Material `Colors.red`: use a cor do DS',
        '6 `20` solto em `width: 20`: nenhum token usado nesta tela tem esse valor; procure no DS (`search`) ou explique '
            'com `f2d:inferred`',
      ],
    );
  });

  test('coleção que é a marca (MarcaA/Spacing/md): a dica escolhe pelo caminho do token, não pela coleção', () {
    final acme = tokenValues(
      {
        'MarcaA/Spacing/md': {'value': 12},
        'MarcaA/Radius/md': {'value': 12},
      },
      Tokens(
        scopes: {
          'Spacing': TokenClass('context.acme.spacing', const {}, {'md'}, theme: true),
          'Radius': TokenClass('context.acme.radius', const {}, {'md'}, theme: true),
        },
      ),
    );
    expect(
      [for (final h in hintsFor('w.dart', 'padding: EdgeInsets.all(12),', tokens: acme)) h['message']],
      ['`12` solto em `EdgeInsets.all(12)` → use `context.acme.spacing.md`'],
    );
  });

  test('o que a tarefa espera: widget a montar, parâmetro proposto e texto do Figma', () {
    final task = {
      'widgets': [
        {'component': 'Template / Extrato', 'widget': 'DsStatementTemplate'},
      ],
      'params': ['avatarInitials'],
      'texts': ['Para quem você quer transferir?'],
    };
    expect(messages('class X { X({required this.name}); }', expect: task), [
      '- `Template / Extrato` deveria virar `DsStatementTemplate` (brief "Componentes a montar"), e não aparece',
      '- parâmetro proposto `avatarInitials` não está no construtor (renomeou? confira os "Usos na tela")',
      '- texto do Figma não aparece: "Para quem você quer transferir?" (se vem de dados ou de tradução, ignore)',
    ]);
    // Placeholder ainda no lugar: o marcador já aparece no check; a dica do widget não repete.
    expect(
      messages(
        '/* f2d:sketch Template / Extrato → DsStatementTemplate */ x; DsX(this.avatarInitials); "Para quem você quer transferir?"',
        expect: task,
      ),
      isEmpty,
    );
  });

  test('resolve grava o que esperar e o check devolve as dicas sem reprovar por elas', () async {
    final app = tempApp(config: 'screens: lib/telas\n');
    final ws = Workspace.find(app.path);
    await resolveTasks(ws, zip, screens: ['03 · Transferir'], mappings: mappingsDir);
    final widget = File('${app.path}/lib/telas/widgets/contact_item.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class ContactItem {
  ContactItem({required this.name, required this.detail});
  final String name;
  final String detail;
  final padding = const EdgeInsets.symmetric(vertical: 12);
}
''');
    final r = await check(ws, [widget.path]);
    final hints = [for (final h in (r['hints'] as List).cast<Json>()) h['message']];
    expect(hints, contains('`12` solto em `EdgeInsets.symmetric(vertical: 12)` → use `DsSpacing.md`'));
    expect(
      hints,
      contains('parâmetro proposto `avatarInitials` não está no construtor (renomeou? confira os "Usos na tela")'),
    );
    expect(
      r['blocking'],
      (r['analyze'] as List).where((i) => (i as Json)['severity'] != 'info').length,
    ); // dica não conta
  });

  test('texto escrito certo em Dart (com escape) não vira dica; texto repetido no Figma vira uma dica só', () {
    final task = {
      'texts': [r'R$ 150,00', "Olá d'água", 'Linha 1\nLinha 2', 'Falta', 'Falta'],
    };
    expect(messages(r"Text('R\$ 150,00'); Text('Olá d\'água'); Text('Linha 1\nLinha 2');", expect: task), [
      '- texto do Figma não aparece: "Falta" (se vem de dados ou de tradução, ignore)',
    ]);
  });

  test('valor solto em chamada quebrada em linhas: a linha certa; f2d:inferred cala só a linha dele', () {
    expect(
      messages('padding: const EdgeInsets.only(\n  left: 12,\n  top: 12, // f2d:inferred — alinhado ao ícone\n),\n'),
      [
        '2 `12` solto em `EdgeInsets.only( left: 12, top: 12, // f2d:inferred — alinhado ao ícone )` → use '
            '`DsSpacing.md`',
      ],
    );
  });

  test('size: só vira dica quando há token com o valor (tamanho de ícone do Figma é o que o brief manda)', () {
    expect(messages('DsIcon(DsIconName.x, size: 20)'), isEmpty); // sem token
    expect(messages('DsIcon(DsIconName.x, size: 12)'), isEmpty); // 12 é espaçamento e raio, não tamanho
    expect(messages('DsIcon(DsIconName.x, size: 24)'), ['1 `24` solto em `size: 24` → use `DsSize.icon`']);
  });

  test('sketch dentro de componente local: a dica fica no widget do componente, não na tela', () async {
    final app = tempApp(config: 'screens: lib/telas\n');
    final local = instanceNode(key: 'local1', component: 'Statement Card', props: {});
    final ir = {
      ...screenWith([
        {
          ...local,
          'instance': {...local['instance'] as Json, 'remote': false},
        },
      ]),
      'components': [
        {
          'id': '6:1',
          'key': 'local1',
          'name': 'Statement Card',
          'props': <String, Object>{},
          'variants': [
            {
              'id': '6:1',
              'name': 'Statement Card',
              'props': <String, Object>{},
              'tree': {
                'id': '6:1',
                'type': 'COMPONENT',
                'name': 'Statement Card',
                'children': [
                  instanceNode(key: statementKey, component: 'Template / Extrato', props: {'title': 'E'}),
                ],
              },
            },
          ],
        },
      ],
    };
    final export = File('${app.path}/export.json')..writeAsStringSync(jsonEncode(ir));
    final ws = Workspace.find(app.path);
    await resolveTasks(ws, export, mappings: mappingsDir);
    final files = (jsonDecode(File('${ws.tasks}/t/check.json').readAsStringSync()) as Json)['files'] as Json;
    expect((files['lib/telas/t_page.dart'] as Json)['widgets'], isNull);
    expect((files['lib/telas/widgets/statement_card.dart'] as Json)['widgets'], [
      {'component': 'Template / Extrato', 'widget': 'DsStatementTemplate'},
    ]);

    final screen = File('${app.path}/lib/telas/t_page.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('final page = StatementCard();\n');
    final card = File('${app.path}/lib/telas/widgets/statement_card.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('class StatementCard {}\n');
    final hints = [
      for (final h in ((await check(ws, [screen.path, card.path]))['hints'] as List).cast<Json>())
        '${(h['file'] as String).split('/').last} ${h['kind']}',
    ];
    expect(hints, ['statement_card.dart widget']);
  });
}
