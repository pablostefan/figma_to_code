import 'dart:convert';
import 'dart:io';

import 'package:figma2dart/src/brief.dart';
import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/component_brief.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

import 'policy_test.dart' show carteiraConfig;
import 'resolve_test.dart' show instanceNode, screenWith;

Directory temp(String name) {
  final dir = Directory(Directory.systemTemp.createTempSync(name).resolveSymbolicLinksSync());
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

void write(String path, String content) => File(path)
  ..createSync(recursive: true)
  ..writeAsStringSync(content);

/// Pacote de app com um widget (`ContactItem`) e o `@FigmaLocal` dele em `figma/connect/`. O package_config é o do
/// carteira_ds_figma (flutter, figma_connect) com caminhos absolutos, mais o próprio pacote.
Directory appPackage({
  String annotation = "@FigmaLocal(key: 'contact', name: 'ContactItem')",
  String target = 'ContactItem',
}) {
  final app = temp('f2d_local_app');
  write('${app.path}/pubspec.yaml', 'name: app\ndev_dependencies:\n  figma_connect:\n    path: x\n');
  write('${app.path}/lib/widgets/contact_item.dart', '''
import 'package:flutter/widgets.dart';

class ContactItem extends StatelessWidget {
  const ContactItem({required this.name, super.key});

  /// Nome do contato.
  final String name;

  @override
  Widget build(BuildContext context) => Text(name);
}
''');
  write('${app.path}/figma/connect/contact_item.figma.dart', '''
import 'package:app/widgets/contact_item.dart';
import 'package:figma_connect/figma_connect.dart';

$annotation
typedef ContactItemFigma = $target;
''');
  final base = File(carteiraConfig).absolute.parent.uri;
  final config = jsonDecode(File(carteiraConfig).readAsStringSync()) as Json;
  write(
    '${app.path}/.dart_tool/package_config.json',
    jsonEncode({
      ...config,
      'packages': [
        for (final p in (config['packages'] as List).cast<Json>())
          {...p, 'rootUri': '${base.resolve(p['rootUri']! as String)}'},
        {'name': 'app', 'rootUri': app.uri.toString(), 'packageUri': 'lib/'},
      ],
    }),
  );
  return app;
}

/// Pacote de mapeamentos sem mapeamento nenhum, só com o retrato do DS (para a regra do gap).
MappingSet withLibrary(Map<String, String> keys) => MappingSet(const [], library: keys);

void main() {
  test('@FigmaLocal: a instância vira montagem do widget do app, com import e API no brief', () async {
    final app = appPackage();
    final (:locals, :warnings) = await loadLocalMappings(app.path);
    expect(warnings, isEmpty);
    expect(locals.single.coverage, 'local');
    expect(locals.single.widget!.name, 'ContactItem');

    final maps = withLibrary({'btn': 'Button'}).withLocal(locals);
    final s = Resolver(maps).screen(
      screenWith([
        instanceNode(key: 'contact', component: 'ContactItem', props: {'name': 'Ana'}, remote: false),
      ]),
    );
    final i = s.instances.single;
    expect(i.status, 'local');
    expect(i.code, startsWith('/* f2d:local ContactItem → ContactItem */'));
    final task = s.components.single;
    expect((task.kind, task.toJson()['import']), ('local', 'package:app/widgets/contact_item.dart'));

    final md = componentBrief(task);
    expect(md, contains('Widget do app (fora do DS)'));
    expect(md, contains("import 'package:app/widgets/contact_item.dart';"));
    expect(md, contains('required String name'));
    expect(md, contains('não altere o `ContactItem` sem perguntar'));
    expect(brief(s), contains('(do app)'));
  });

  test('retrato do DS: key do DS sem mapeamento é gap; remoto de outra biblioteca é a construir', () {
    final s = Resolver(withLibrary({'btn': 'Button'})).screen(
      screenWith([
        instanceNode(key: 'btn', component: 'Button', props: {}, remote: true),
        instanceNode(key: 'produto', component: 'CardPix', props: {}, remote: true),
      ]),
    );
    expect(s.instances.map((i) => i.status), ['gap', 'placeholder']);
    // Sem retrato vale a regra antiga: remoto é do DS.
    final old = Resolver(
      MappingSet(const []),
    ).screen(screenWith([instanceNode(key: 'produto', component: 'CardPix', props: {}, remote: true)]));
    expect(old.instances.single.status, 'gap');
  });

  test('@FigmaLocal com problema fica de fora com aviso, sem travar a tela', () async {
    final (:locals, warnings: _) = await loadLocalMappings(appPackage().path);
    final ds = withLibrary({'contact': 'Contato'}).withLocal(locals);
    expect(ds.components, isEmpty);
    expect(ds.warnings.single, contains('é do DS (Contato)'));
    final twice = MappingSet(const []).withLocal([...locals, ...locals]);
    expect(twice.components, hasLength(1));
    expect(twice.warnings.single, contains('já tem mapeamento'));

    // Widget renomeado sem atualizar a anotação: não compila. O componente volta a ser a construir.
    final stale = await loadLocalMappings(appPackage(target: 'ContactRow').path);
    expect(stale.locals, isEmpty);
    expect(stale.warnings.single, contains("não compila: Undefined class 'ContactRow'"));
    final s = Resolver(
      MappingSet(const []).withLocal(stale.locals, warnings: stale.warnings),
    ).screen(screenWith([instanceNode(key: 'contact', component: 'ContactItem', props: {}, remote: false)]));
    expect(s.instances.single.status, 'placeholder');

    final wrong = await loadLocalMappings(
      appPackage(annotation: "@FigmaConnect(key: 'contact', name: 'ContactItem')").path,
    );
    expect(wrong.warnings.single, contains('fica no pacote de mapeamentos'));
  });

  group('comandos', () {
    late Directory repo;
    late Workspace ws;
    setUp(() {
      repo = temp('f2d_local_repo');
      write(
        '${repo.path}/ds_figma/pubspec.yaml',
        'name: ds_figma\ndependencies:\n  ds:\n    path: ../ds\n  figma_connect:\n    path: ../fc\n',
      );
      // O DS tem uma classe com o mesmo nome do componente do app: não pode virar pista nem receber `link`.
      write('${repo.path}/ds/pubspec.yaml', 'name: ds\n');
      write('${repo.path}/ds/lib/contact_item.dart', 'class ContactItem {}\nclass Botao {}\n');
      write('${repo.path}/app/pubspec.yaml', 'name: app\ndependencies:\n  ds:\n    path: ../ds\n');
      write('${repo.path}/app/${Workspace.configName}', 'mappings: ../ds_figma\n');
      write('${repo.path}/app/lib/widgets/contact_item.dart', 'class ContactItem {}\nclass _Private {}\n');
      ws = Workspace.find('${repo.path}/app');
    });

    Json libraryIr(String page, Map<String, String> components) => {
      'kind': 'library',
      'source': {'fileName': 'Acme', 'pageName': page, 'exportedAt': '2026-10-25'},
      'components': [
        for (final MapEntry(:key, :value) in components.entries) {'key': key, 'name': value},
      ],
    };

    String export(String name, Json ir) {
      write('${repo.path}/$name', jsonEncode(ir));
      return '${repo.path}/$name';
    }

    test('library: uma página por export; a mesma página de novo substitui', () {
      final a = export('a.json', libraryIr('Botões', {'b1': 'Button', 'b2': 'IconButton'}));
      final b = export('b.json', libraryIr('Listas', {'l1': 'List'}));
      expect(library(ws, [a, b])['components'], 3);
      final again = export('c.json', libraryIr('Botões', {'b1': 'Button'}));
      expect(library(ws, [again])['components'], 2);
      final snapshot = jsonDecode(File('${repo.path}/ds_figma/$libraryFile').readAsStringSync()) as Json;
      expect(libraryKeys(snapshot), {'b1': 'Button', 'l1': 'List'});

      final screen = export('d.json', {'kind': 'screen', 'source': <String, Object?>{}, 'components': <Object>[]});
      expect(() => library(ws, [screen]), throwsA(isA<ResolveError>()));
    });

    test('link: escreve o @FigmaLocal no pacote do widget; key do DS e outra key no mesmo arquivo são erro', () async {
      // figma_connect já nas dev_dependencies: o link não roda `pub add`.
      write(
        '${repo.path}/app/pubspec.yaml',
        'name: app\ndependencies:\n  ds:\n    path: ../ds\ndev_dependencies:\n  figma_connect:\n    path: ../fc\n',
      );
      // Keys do Figma têm 40 caracteres hex; a curta (8, a do placeholder) é erro antes de tudo.
      final contact = 'c' * 40, other = 'a' * 40, dsKey = 'b' * 40;
      expect(
        () => link(ws, 'cccccccc', '${repo.path}/app/lib/widgets/contact_item.dart'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('incompleta'))),
      );
      final r = await link(ws, contact, '${repo.path}/app/lib/widgets/contact_item.dart#ContactItem', name: 'Contato');
      expect(r['import'], 'package:app/widgets/contact_item.dart');
      expect(r.containsKey('devDependency'), isFalse);
      final file = File('${repo.path}/app/figma/connect/contact_item.figma.dart').readAsStringSync();
      expect(file, contains("@FigmaLocal(key: '$contact', name: 'Contato')\ntypedef ContactItemFigma = ContactItem;"));
      expect(file, contains("import 'package:app/widgets/contact_item.dart';"));
      expect((await link(ws, contact, '${repo.path}/app/lib/widgets/contact_item.dart'))['written'], isFalse);
      expect(
        () => link(ws, other, '${repo.path}/app/lib/widgets/contact_item.dart'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('outra key'))),
      );

      library(ws, [
        export('l.json', libraryIr('Botões', {dsKey: 'Button'})),
      ]);
      expect(
        () => link(ws, dsKey, '${repo.path}/app/lib/widgets/contact_item.dart'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('é do DS'))),
      );
      expect(
        () => link(ws, other, '${repo.path}/ds/lib/contact_item.dart'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('é do DS'))),
      );
      // Pacote que não é dependência direta do pacote da tela: o resolve nunca leria a anotação.
      write('${repo.path}/outro/pubspec.yaml', 'name: outro\n');
      write('${repo.path}/outro/lib/x.dart', 'class X {}\n');
      expect(
        () => link(ws, other, '${repo.path}/outro/lib/x.dart'),
        throwsA(isA<ResolveError>().having((e) => e.message, 'message', contains('dependência direta'))),
      );
      // Caminho com `..` (ou link simbólico) chega ao mesmo arquivo.
      expect(
        (await link(ws, contact, '${repo.path}/app/lib/widgets/../widgets/contact_item.dart'))['written'],
        isFalse,
      );
    });

    test('screens: "fora do DS" pelo retrato quando existe', () {
      final ir = {
        'kind': 'screen',
        'screens': [
          {
            'name': 'T',
            'states': [
              {
                'state': 'default',
                'id': '1:1',
                'tree': {
                  'children': [
                    {
                      'instance': {'componentKey': 'b1', 'remote': true},
                    },
                    {
                      'instance': {'componentKey': 'outra', 'remote': true},
                    },
                  ],
                },
              },
            ],
          },
        ],
      };
      final file = File(export('s.json', ir));
      int outside(Json r) =>
          (((r['screens'] as List).single as Json)['states'] as List).cast<Json>().single['outsideDs']! as int;
      expect(outside(screens(file)), 0); // sem retrato: remoto é do DS
      library(ws, [
        export('l.json', libraryIr('Botões', {'b1': 'Button'})),
      ]);
      expect(outside(screens(file, library: ws.library())), 1);
    });

    test('findClasses: a pista de componente que já existe no app (não no DS)', () {
      expect(ws.findClasses({'ContactItem', 'Outro'}), {
        'ContactItem': '${repo.path}/app/lib/widgets/contact_item.dart',
      });
      expect(ws.findClasses({'Botao'}), isEmpty); // classe só do DS não é pista
    });
  });
}
