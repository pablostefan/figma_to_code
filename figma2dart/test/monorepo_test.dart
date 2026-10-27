import 'dart:convert';
import 'dart:io';

import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart' show Json;
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

/// Monorepo mínimo como o real: raiz do melos sem `lib/`, Acme e mapeamentos no design_ops, config ao lado da CLI e
/// pacotes de setor. Os arquivos ficam no índice do git (`git add`), que é por onde a CLI acha tudo.
Directory monorepo(Map<String, String> files) {
  final dir = Directory(Directory.systemTemp.createTempSync('f2d_mono').resolveSymbolicLinksSync());
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry(key: path, value: content) in files.entries) {
    File('${dir.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
  for (final args in [
    ['init', '-q'],
    ['add', '-A'],
  ]) {
    expect(Process.runSync('git', args, workingDirectory: dir.path).exitCode, 0);
  }
  return dir;
}

const ops = 'libraries/design_ops/packages';

final base = {
  'pubspec.yaml': 'name: monorepo\n',
  'melos.yaml': 'name: monorepo\n',
  '$ops/acme/pubspec.yaml': 'name: acme\n',
  '$ops/acme/lib/acme.dart': '',
  '$ops/acme_figma/pubspec.yaml':
      'name: acme_figma\ndependencies:\n  acme:\n    path: ../acme\n  figma_connect:\n    path: ../figma2dart/figma_connect\n',
  '$ops/acme_figma/lib/figma_policy.dart': '',
  '$ops/figma2dart/figma_to_dart.yaml': 'mappings: ../acme_figma\nscreens: lib/figma\n',
  'libraries/pix/pix_ui/pubspec.yaml':
      'name: pix_ui\ndependencies:\n  acme:\n    path: ../../design_ops/packages/acme\n',
  'libraries/pix/pix_ui/lib/a/a.dart': '',
  'libraries/pix/pix_ui/figma_to_dart.yaml': 'screens: lib/telas\n',
  'libraries/pix/pix_ui/example/pubspec.yaml': 'name: pix_ui_example\n',
  'libraries/pix/pix_core/pubspec.yaml': 'name: pix_core\n',
};

void main() {
  test('de dentro do pacote do setor: config do repo pelo git, o do pacote vence, Acme pelo config', () {
    final repo = monorepo(base);
    final ws = Workspace.find('${repo.path}/libraries/pix/pix_ui/lib/a');
    expect(ws.app, '${repo.path}/libraries/pix/pix_ui');
    expect(ws.repo, repo.path);
    expect(ws.configs.keys, ['${repo.path}/$ops/figma2dart/figma_to_dart.yaml', '${ws.app}/figma_to_dart.yaml']);
    expect(ws.screens, 'lib/telas');
    final m = ws.mappings()!;
    expect((m.path, m.via), ('${repo.path}/$ops/acme_figma', 'config'));
    expect(ws.dsPackages(), {'acme'});
  });

  test('da raiz: pede --package; com ele, ou para `packages`, funciona', () {
    final repo = monorepo(base);
    expect(() => Workspace.find(repo.path), throwsA(isA<ResolveError>()));
    final pix = Workspace.find(repo.path, package: '${repo.path}/libraries/pix/pix_core');
    expect((pix.app, pix.screens), ('${repo.path}/libraries/pix/pix_core', 'lib/figma')); // padrão do repo

    final r = packages(Workspace.find(repo.path, anywhere: true), 'pix');
    expect(
      [for (final p in (r['packages'] as List).cast<Json>()) (p['relative'], p['ds'])],
      [
        ('libraries/pix/pix_ui', true), // usa o Acme: primeiro
        ('libraries/pix/pix_core', false),
      ],
    ); // example/ fica de fora
  });

  test('sem `mappings:`, o Acme é o único pacote com lib/figma_policy.dart', () {
    final repo = monorepo({...base, '$ops/figma2dart/figma_to_dart.yaml': 'screens: lib/figma\n'});
    final m = Workspace.find('${repo.path}/libraries/pix/pix_ui').mappings()!;
    expect((m.path, m.via), ('${repo.path}/$ops/acme_figma', 'repositório'));
  });

  test('config com o nome antigo (figma2dart.yaml) não é lido; o doctor pede para renomear', () {
    final repo = monorepo({
      for (final MapEntry(:key, :value) in base.entries)
        if (!key.endsWith('figma2dart/figma_to_dart.yaml')) key: value,
      '$ops/figma2dart/figma2dart.yaml': 'mappings: ../acme_figma\n',
    });
    final ws = Workspace.find('${repo.path}/libraries/pix/pix_core');
    expect(ws.configs, isEmpty);
    expect(ws.legacyConfigs, ['${repo.path}/$ops/figma2dart/figma2dart.yaml']);
  });

  test('dois configs com `mappings:` é erro', () {
    final repo = monorepo({...base, 'libraries/pix/pix_ui/figma_to_dart.yaml': 'mappings: ../outro\n'});
    expect(() => Workspace.find('${repo.path}/libraries/pix/pix_ui'), throwsA(isA<ResolveError>()));
  });

  test('ensurePubGet roda só quando falta o package_config ou o pubspec mudou', () {
    final repo = monorepo({'p/pubspec.yaml': 'name: p\nenvironment:\n  sdk: ^3.0.0\n'});
    final config = File('${repo.path}/p/.dart_tool/package_config.json');
    ensurePubGet('${repo.path}/p');
    expect(config.existsSync(), isTrue);
    final first = config.lastModifiedSync();
    ensurePubGet('${repo.path}/p');
    expect(config.lastModifiedSync(), first);
    // pubspec tocado sem mudar dependência (git pull, troca de branch): o pub não regrava o package_config; a CLI
    // atualiza a data, senão rodaria pub get em toda chamada.
    File('${repo.path}/p/pubspec.yaml').setLastModifiedSync(first.add(const Duration(seconds: 5)));
    ensurePubGet('${repo.path}/p');
    final refreshed = config.lastModifiedSync();
    expect(refreshed.isAfter(first), isTrue);
    ensurePubGet('${repo.path}/p');
    expect(config.lastModifiedSync(), refreshed);
  });

  test('setup instala o script; ele roda a CLI de onde foi chamado e devolve JSON limpo', () async {
    final bin = Directory.systemTemp.createTempSync('f2d_bin');
    addTearDown(() => bin.deleteSync(recursive: true));
    final r = await setup(bin: bin.path);
    final script = File(r['installed']! as String);
    expect(script.readAsStringSync(), contains("fallback='${Directory.current.path}'"));

    final repo = monorepo(base);
    final run = Process.runSync(script.path, ['packages', 'pix', '--json'], workingDirectory: '${repo.path}/libraries');
    expect(run.exitCode, 0, reason: '${run.stderr}');
    final json = jsonDecode(run.stdout as String) as Json; // stdout só com o JSON
    expect((json['packages'] as List).map((p) => (p as Json)['relative']), contains('libraries/pix/pix_ui'));
  });
}
