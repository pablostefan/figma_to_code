import 'dart:io';

import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/hints.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

import 'commands_test.dart' show mappingsDir, tempApp, zip;

void main() {
  const tokens = {
    '12': [
      {'code': 'DsSpacing.md', 'collection': 'Spacing'},
      {'code': 'DsRadius.md', 'collection': 'Radius'},
    ],
    '#64748B': [
      {'code': 'DsPrimitives.gray500', 'collection': 'Primitives'},
      {'code': 'DsColors.textSecondary', 'collection': 'Color'},
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
        '6 `20` solto em `width: 20`: use um token do DS (nenhum tem esse valor) ou explique com `f2d:inferred`',
      ],
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
}
