import 'dart:convert';
import 'dart:io';

import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/export.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

const mappingsDir = '../../design_system/carteira_ds_figma';
final zip = File('test/fixtures/flow.plugin.zip');

/// App Flutter mínimo numa pasta temporária: só o que a descoberta lê.
Directory tempApp({String? config, List<Json> packages = const []}) {
  final dir = Directory.systemTemp.createTempSync('f2d_app');
  addTearDown(() => dir.deleteSync(recursive: true));
  File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
  if (config != null) File('${dir.path}/${Workspace.configName}').writeAsStringSync(config);
  File('${dir.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'app', 'rootUri': '../', 'packageUri': 'lib/'},
          ...packages,
        ],
      }),
    );
  return dir;
}

void main() {
  final mappingsUri = Directory(mappingsDir).absolute.uri.toString();

  group('Workspace', () {
    test('acha o app subindo de uma subpasta e os mapeamentos pelas dependências', () {
      final app = tempApp(
        packages: [
          {'name': 'carteira_ds_figma', 'rootUri': mappingsUri, 'packageUri': 'lib/'},
        ],
      );
      final ws = Workspace.find((Directory('${app.path}/lib/a')..createSync(recursive: true)).path);
      expect(ws.app, app.path);
      final m = ws.mappings()!;
      expect(m.path, Directory(mappingsDir).resolveSymbolicLinksSync());
      expect(m.via, 'dependência do pacote');
      expect(m.packageConfig, '${app.path}/.dart_tool/package_config.json');
    });

    test('config manda: mappings relativo ao app, exports e screens', () {
      final exports = Directory.systemTemp.createTempSync('f2d_exports');
      addTearDown(() => exports.deleteSync(recursive: true));
      final old = File('${exports.path}/figma2dart-flow-a.zip')..writeAsStringSync('');
      old.setLastModifiedSync(DateTime(2020));
      File('${exports.path}/figma2dart-screen-b.zip').writeAsStringSync('');
      File('${exports.path}/outro.zip').writeAsStringSync('');
      final app = tempApp(config: 'mappings: ../ds_figma\nexports: ${exports.path}\nscreens: lib/telas\n');
      final ws = Workspace.find(app.path);
      expect(ws.mappings()!.via, 'config');
      expect(ws.mappings()!.path, '${app.parent.path}/ds_figma');
      expect(ws.screens, 'lib/telas');
      expect(ws.exports().map((f) => f.uri.pathSegments.last), ['figma2dart-screen-b.zip', 'figma2dart-flow-a.zip']);
    });

    test('fora de um app explica o que fazer', () {
      expect(() => Workspace.find('/'), throwsA(isA<ResolveError>()));
    });
  });

  test('screens: ordem do fluxo, início e instâncias fora do DS', () {
    final r = screens(zip);
    final list = (r['screens'] as List).cast<Json>();
    expect(list.map((s) => s['name']), hasLength(5));
    final states = [for (final s in list) (s['states'] as List).single as Json];
    expect(states.map((s) => s['start']), [true, false, false, false, false]);
    expect(states.map((s) => s['outsideDs']), [0, 0, 4, 5, 1]);
  });

  test('resolve: pasta da tarefa, arquivo da tela e dos widgets, navegação e estrutura no brief', () async {
    final app = tempApp(config: 'screens: lib/telas\n');
    final ws = Workspace.find(app.path);
    final both = await resolveTasks(ws, zip, screens: ['03 · Transferir', '04 · Confirmar'], mappings: mappingsDir);
    final tasks = (both['tasks'] as List).cast<Json>();
    expect(tasks.map((t) => t['screen']), ['03 · Transferir', '04 · Confirmar']);
    final r = tasks.last;
    // Mesmo nome sem a numeração ("Sucesso") em duas telas pedidas juntas: pastas diferentes, nada é apagado.
    final ir = Export.read(zip.path).ir;
    final copy = {
      ...ir,
      'screens': [
        ...(ir['screens'] as List).cast<Json>(),
        for (final sc in (ir['screens'] as List).cast<Json>())
          if (sc['name'] == '05 · Sucesso')
            {
              ...sc,
              'name': '07 · Sucesso',
              'states': [
                for (final st in (sc['states'] as List).cast<Json>())
                  {...st, 'id': '9:999', 'frameName': '07 · Sucesso'},
              ],
            },
      ],
    };
    final json = File('${app.path}/dup.json')..writeAsStringSync(jsonEncode(copy));
    final dup = await resolveTasks(ws, json, screens: ['05 · Sucesso', '07 · Sucesso'], mappings: mappingsDir);
    expect(
      [for (final t in (dup['tasks'] as List).cast<Json>()) t['screenFile']],
      ['${ws.app}/lib/telas/sucesso_page.dart', '${ws.app}/lib/telas/sucesso_9_999_page.dart'],
    );
    expect(
      [for (final t in (dup['tasks'] as List).cast<Json>()) Directory(t['dir']! as String).existsSync()],
      [true, true],
    );
    // Pasta padrão recomeça a cada resolve: brief de componente que saiu da tela não fica.
    final stale = Directory('${r['dir']}/components/sumiu')..createSync(recursive: true);
    await resolveTasks(ws, zip, screens: ['04 · Confirmar'], mappings: mappingsDir);
    expect(stale.existsSync(), isFalse);
    expect(r['dir'], '${app.path}/.figma2dart/tasks/confirmar');
    expect(r['screenFile'], '${ws.app}/lib/telas/confirmar_page.dart');
    expect(File(r['image']! as String).existsSync(), isTrue);
    final components = (r['components'] as List).cast<Json>();
    expect(components.map((c) => c['widgetFile']), contains('${ws.app}/lib/telas/widgets/summary_row.dart'));
    expect(File(components.first['brief']! as String).existsSync(), isTrue);
    final md = File(r['brief']! as String).readAsStringSync();
    expect(md, contains('## Estrutura da tela'));
    expect(md, contains('`SummaryRow`: componente local **SummaryRow** → [brief](components/summary_row/BRIEF.md)'));
    expect(md, contains('props {"value":"R\$ 150,00","label":"Valor"}'));
    expect(md, contains('`actions/Button/Confirmar transferência` (7:413) → **05 · Sucesso**'));
    expect(md, contains('`TopBar` (7:383) → voltar'));
  });

  test('check: marcador bloqueante e erro do analyze reprovam; inferred só é contado', () async {
    final app = tempApp();
    final file = File('${app.path}/lib/tela.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("int a = /* f2d:guided G1 a */ 1; // f2d:inferred G1 — teste\nint b = 'x';\n");
    final r = await check(Workspace.find(app.path), [file.path]);
    expect(r['ok'], isFalse);
    expect(r['blocking'], 2);
    expect(r['inferred'], 1);
    expect((r['analyze'] as List).cast<Json>().single['code'], 'invalid_assignment');

    // Caminho relativo à pasta de onde se chama (a raiz do monorepo), não à do pacote: o analyze ainda vê o erro.
    final up = '../' * Directory.current.uri.pathSegments.where((s) => s.isNotEmpty).length;
    final relative = await check(Workspace.find(app.path), ['$up${file.absolute.path.substring(1)}']);
    expect((relative['analyze'] as List).cast<Json>().single['code'], 'invalid_assignment');

    // TODO(f2d) é pendência do dev: conta, mas não reprova.
    file.writeAsStringSync('int a = 1; // f2d:inferred G1 — teste\nint b = /* TODO(f2d): ícone */ 0;\n');
    final ok = await check(Workspace.find(app.path), [file.path]);
    expect((ok['ok'], ok['todos']), (true, 1));
  });

  test('init: config, .gitignore, agente e skills; segunda vez não sobrescreve', () async {
    final app = tempApp();
    File('${app.path}/.gitignore').writeAsStringSync('build/');
    final ws = Workspace.find(app.path);
    final first = await init(ws);
    expect(
      first['written'],
      containsAll([
        Workspace.configName,
        '.gitignore',
        '.github/agents/figma-to-flutter.agent.md',
        '.github/agents/figma-component-builder.agent.md',
        '.github/agents/figma-visual-reviewer.agent.md',
        '.agents/skills/figma2dart-setup/SKILL.md',
        '.agents/skills/figma2dart-screen/SKILL.md',
        '.agents/skills/figma2dart-component/SKILL.md',
        '.agents/skills/figma2dart-review/SKILL.md',
      ]),
    );
    expect(File('${app.path}/.gitignore').readAsStringSync(), 'build/\n.figma2dart/\n');
    final second = await init(ws);
    expect(second['written'], isEmpty);
    expect(second['skipped'], hasLength(8));

    File('${app.path}/${Workspace.configName}').writeAsStringSync('screens: lib/telas\n');
    final forced = await init(ws, force: true);
    expect(forced['written'], hasLength(7)); // agentes e skills
    expect(Workspace.find(app.path).screens, 'lib/telas');
  });

  test('links do agente para as skills batem com onde o init instala', () {
    final agents = Directory('agent/agents').listSync().whereType<File>();
    for (final agent in agents) {
      for (final link in RegExp(r'\]\((\.\./\.\./\.agents/skills/[^)]+)\)').allMatches(agent.readAsStringSync())) {
        final installed = link[1]!.replaceFirst('../../.agents/', 'agent/');
        expect(File(installed).existsSync(), isTrue, reason: '${agent.path} → ${link[1]}');
      }
    }
  });
}
