// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;
import 'package:yaml/yaml.dart';

import 'brief.dart';
import 'component_brief.dart';
import 'crop.dart';
import 'review.dart';
import 'export.dart';
import 'hints.dart';
import 'mappings.dart';
import 'names.dart';
import 'resolve.dart';
import 'workspace.dart';

/// O que o agente precisa saber antes de começar: onde está cada coisa e o que falta, com a correção.
Future<Json> doctor(Workspace ws) async {
  final problems = <Json>[];
  // Não impedem de seguir, mas o agente avisa o usuário.
  final warnings = <Json>[];
  Json? mappings;
  Json? library;
  try {
    final m = ws.mappings();
    if (m == null) {
      problems.add({
        'what': 'pacote de mapeamentos não encontrado',
        'fix':
            'adicionar o pacote de mapeamentos do DS como dev_dependency do app e rodar `flutter pub get`, ou '
            'apontar `mappings:` no ${Workspace.configName}',
      });
    } else {
      // O mesmo carregamento do `resolve`: DS e `@FigmaLocal` do app, para o doctor ver o que o resolve vai ver.
      final set = await ws.loadMappingsOrFail();
      final local = set.components.where((c) => c.coverage == 'local').length;
      mappings = {'path': m.path, 'via': m.via, 'components': set.components.length - local, 'local': local};
      for (final w in set.warnings) {
        warnings.add({
          'what': '@FigmaLocal ignorado: $w',
          'fix': 'corrigir ou apagar o arquivo; até lá o componente volta a ser "a construir"',
        });
      }
      final snapshot = File('${m.path}/$libraryFile');
      if (snapshot.existsSync()) {
        final pages = ((jsonDecode(snapshot.readAsStringSync()) as Json)['pages'] as Map).cast<String, Json>();
        library = {
          for (final MapEntry(:key, value: page) in pages.entries)
            key: {'exportedAt': page['exportedAt'], 'components': (page['components'] as Map).length},
        };
      } else {
        warnings.add({
          'what': 'sem retrato do DS ($libraryFile): componente de outra biblioteca do Figma sai como gap do DS',
          'fix': 'exportar cada página de componentes do DS no plugin (sem seleção) e rodar `figma2dart library`',
        });
      }
    }
  } on Object catch (e) {
    problems.add({'what': 'mapeamentos com erro: ${e is ArgumentError ? e.message : e}', 'fix': 'corrigir o pacote'});
  }
  if (ws.configs.isEmpty) {
    problems.add({
      'what': 'nenhum ${Workspace.configName}',
      'fix': 'no monorepo: versionar (git add) o config com `mappings:`; num app só: rodar `figma2dart init`',
    });
  }
  final exports = ws.exports();
  if (exports.isEmpty) {
    problems.add({
      'what': 'nenhum figma2dart-*.zip em ${ws.exportsDir}',
      'fix': 'exportar pelo plugin figma2dart no Figma, ou passar o caminho do .zip, ou apontar `exports:` no config',
    });
  }
  if (ws.screens == null) {
    problems.add({
      'what': 'pasta das telas não definida',
      'fix': 'ver onde o app guarda as telas, confirmar com o usuário e gravar `screens:` no ${Workspace.configName}',
    });
  }
  return {
    'app': ws.app,
    'repo': ws.repo,
    'configs': ws.configs.keys.toList(),
    'mappings': mappings,
    'screens': ws.screens,
    'tasks': ws.tasks,
    'exportsDir': ws.exportsDir,
    'exports': [
      for (final f in exports.take(5)) {'path': f.path, 'modified': f.lastModifiedSync().toIso8601String()},
    ],
    'library': library,
    'ok': problems.isEmpty,
    'problems': problems,
    'warnings': warnings,
  };
}

/// O export a usar: o caminho dado ou o mais novo da pasta de exports.
File exportFile(Workspace ws, String? path) {
  if (path != null) return File(path);
  return ws.exports().firstOrNull ??
      (throw ResolveError('Nenhum export informado e nenhum figma2dart-*.zip em ${ws.exportsDir}.'));
}

/// Telas e estados do export, na ordem do fluxo quando há um, com quantas instâncias ficam fora do DS ([library]: o
/// retrato do DS; sem ele, o que não é remoto).
Json screens(File file, {Map<String, String>? library}) {
  final ir = Export.read(file.path).ir;
  final start = (ir['flow'] as Json?)?['start'];
  final list = (ir['screens'] as List? ?? const []).cast<Json>();
  int count(Json node, bool Function(Json) test) => switch (node['instance']) {
    final Json i => test(i) ? 1 : 0,
    _ => (node['children'] as List? ?? const []).cast<Json>().fold(0, (n, c) => n + count(c, test)),
  };
  return {
    'export': file.path,
    'kind': ir['kind'],
    'file': (ir['source'] as Json?)?['fileName'],
    'screens': [
      for (final s in list)
        {
          'name': s['name'],
          'states': [
            for (final st in (s['states'] as List).cast<Json>())
              {
                'state': st['state'],
                'frameId': st['id'],
                'start': st['id'] == start,
                'instances': count(st['tree'] as Json, (_) => true),
                'outsideDs': count(
                  st['tree'] as Json,
                  (i) => library == null
                      ? i['remote'] != true
                      : !library.containsKey(i['componentKey']) && !library.containsKey(i['mainComponentKey']),
                ),
              },
          ],
        },
    ],
    'navigation': ((ir['flow'] as Json?)?['edges'] as List? ?? const []).length,
  };
}

/// Resolve as [screens] (todas de uma vez, com uma carga só dos mapeamentos) e escreve uma pasta de tarefa por tela.
/// Sem [screens], a única tela do export.
Future<Json> resolveTasks(
  Workspace ws,
  File file, {
  List<String> screens = const [],
  String? state,
  String? out,
  String? mappings,
}) async {
  if (out != null && screens.length > 1) throw ResolveError('--out vale para uma tela só.');
  final export = Export.read(file.path);
  final maps = await ws.loadMappingsOrFail(override: mappings);
  final taken = <String>{};
  return {
    'export': file.path,
    // `@FigmaLocal` que ficou de fora (não compila, key do DS…): o agente conta ao usuário.
    if (maps.warnings.isNotEmpty) 'warnings': maps.warnings,
    'tasks': [
      for (final screen in screens.isEmpty ? <String?>[null] : screens)
        _task(ws, export, maps, taken, screen: screen, state: state, out: out),
    ],
  };
}

Json _task(
  Workspace ws,
  Export export,
  MappingSet maps,
  Set<String> taken, {
  String? screen,
  String? state,
  String? out,
}) {
  final s = Resolver(maps).screen(export.ir, screen: screen, state: state);
  // Duas telas com o mesmo nome sem a numeração (`03 · Sucesso`, `07 · Sucesso`) não podem dividir a pasta.
  final base = screenSlug(s.screen);
  final slug = taken.add(base) ? base : '${base}_${s.frameId.replaceAll(RegExp('[^0-9]+'), '_')}';
  taken.add(slug);
  final dir = Directory(out ?? '${ws.tasks}/$slug');
  // A pasta padrão é só da ferramenta: recomeça do zero, para não sobrar brief de componente que saiu da tela.
  if (out == null && dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  const json = JsonEncoder.withIndent('  ');
  File('${dir.path}/resolved.json').writeAsStringSync(json.convert(s.toJson()));
  final images = export.copyImages(s, dir);
  final screenFile = ws.screens == null ? null : '${ws.screens}/${slug}_page.dart';
  // O que o `check` confere nesta tarefa (dicas, não reprova): tokens por valor e, por arquivo, widgets a montar,
  // parâmetros e textos.
  final builds = {for (final c in s.components.where((c) => c.sketch == null)) c.name: c};
  String? widgetFile(ComponentTask c) => ws.screens == null ? null : '${ws.screens}/widgets/${c.folder}.dart';
  final files = <String, Json>{
    if (screenFile != null) screenFile: {'texts': staticTexts(s.tree).toSet().toList()},
    for (final c in builds.values)
      if (widgetFile(c) case final file?) file: {
        'params': apiParams(c),
        'texts': {
          for (final v in (c.definition?['variants'] as List? ?? const []).cast<Json>())
            ...staticTexts(v['tree'] as Json),
        }.toList(),
      },
  };
  // Widget a montar vai no arquivo de quem o usa: a tela, ou o componente local que o tem dentro (`within`).
  for (final c in s.components) {
    final widget = c.sketch?.widget;
    if (widget == null) continue;
    for (final owner in {for (final u in c.uses) c.within[u.id]}) {
      final path = owner == null
          ? screenFile
          : switch (builds[owner]) {
              final b? => widgetFile(b),
              null => null,
            };
      if (path != null) {
        (((files[path] ??= {})['widgets'] ??= <Json>[]) as List).add({'component': c.name, 'widget': widget.name});
      }
    }
  }
  File('${dir.path}/check.json').writeAsStringSync(
    json.convert({
      if (maps.policy.tokens case final tokens?)
        'tokens': tokenValues((export.ir['tokens'] as Json?) ?? const {}, tokens),
      'files': files,
    }),
  );
  File('${dir.path}/BRIEF.md').writeAsStringSync(brief(s, images: images));
  // Para a revisão visual: o tamanho do frame (captura), os textos e as seções com a estrutura (`review`).
  File('${dir.path}/review.json').writeAsStringSync(json.convert(reviewInput(s, images: images)));
  // PNG da tela decodificado uma vez, só se algum componente a montar tiver instância para recortar.
  img.Image? screenPng;
  var decoded = false;
  for (final c in s.components) {
    final cdir = Directory('${dir.path}/components/${c.folder}')..createSync(recursive: true);
    // Recorte de cada instância a montar (sketch/local) na tela: a LLM vê só o pedaço que vai montar.
    final crops = <String, String>{};
    if (c.sketch != null && s.image != null) {
      for (final u in c.uses.where((u) => u.bounds != null && !c.within.containsKey(u.id))) {
        if (!decoded) {
          decoded = true;
          if (export.file(s.image!) case final png?) screenPng = img.decodePng(png);
          // PNG maior que o frame: recorte deslocado engana mais do que ajuda; fica só a imagem da tela.
          if (screenPng != null && !coversFrame(screenPng, s.tree['size'] as Json?, s.imageScale)) screenPng = null;
        }
        if (screenPng == null) break;
        if (crop(screenPng, u.bounds!, s.imageScale) case final bytes?) {
          final name = '${u.id.replaceAll(RegExp('[^0-9A-Za-z]+'), '-')}.png';
          File('${cdir.path}/$name').writeAsBytesSync(bytes);
          crops[u.id] = name;
        }
      }
    }
    final md = componentBrief(
      c,
      folders: (i) => taskOf(s, i)?.folder,
      images: images,
      references: s.references[c.name],
      screenImage: images.contains(s.image) ? s.image : null,
      tokens: s.tokens,
      crops: crops,
    );
    File('${cdir.path}/BRIEF.md').writeAsStringSync(md);
    for (final v in (c.definition?['variants'] as List? ?? const []).cast<Json>()) {
      if (v['svg'] case final String svg) File('${cdir.path}/${svgFile(v)}').writeAsStringSync(svg);
    }
    File('${cdir.path}/component.json').writeAsStringSync(json.convert(c.toJson()));
  }
  int count(String status) => s.instances.where((i) => i.status == status).length;
  // Componente a construir que talvez já exista no app (classe de mesmo nome): o agente pergunta antes.
  final existing = ws.findClasses({
    for (final c in s.components)
      if (c.sketch == null) pascalCase(c.folder),
  });
  return {
    'screen': s.screen,
    'state': s.state,
    'frameId': s.frameId,
    'dir': dir.absolute.path,
    'brief': '${dir.absolute.path}/BRIEF.md',
    'image': images.contains(s.image) ? '${dir.absolute.path}/${s.image}' : null,
    'counts': {
      'mapped': count('mapped'),
      'sketch': count('sketch'),
      'local': count('local'),
      'gap': count('gap'),
      'placeholder': count('placeholder'),
      'guided': s.guided.length,
    },
    // Absolutos, como `brief` e `dir`: o agente pode estar na raiz do monorepo, não no pacote.
    'screenFile': screenFile == null ? null : '${ws.app}/$screenFile',
    'components': [
      for (final c in s.components)
        {
          'name': c.name,
          'key': c.key,
          // build: construir fora do DS (escolha do usuário); sketch/local: montar o widget do DS/do app no lugar
          // do placeholder.
          'kind': c.kind,
          'brief': '${dir.absolute.path}/components/${c.folder}/BRIEF.md',
          'uses': c.uses.length,
          if (c.sketch?.widget case final widget?) ...{
            'widget': widget.name,
            'import': '${widget.library.source.uri}',
          } else ...{
            'class': pascalCase(c.folder),
            'widgetFile': switch (widgetFile(c)) {
              final f? => '${ws.app}/$f',
              null => null,
            },
            'dependsOn': c.dependencies.values.toList(),
            if (existing[pascalCase(c.folder)] case final path?) 'existing': path,
          },
        },
    ],
  };
}

/// Marcadores que impedem a tarefa de estar pronta; `placeholder`, `inferred` e `TODO(f2d)` (pendências do dev) só
/// são listados.
const _blocking = {'guided', 'gap', 'sketch', 'local'};

/// Confere os arquivos gerados: marcadores que sobraram e o `dart analyze` deles (reprovam), e as dicas do que parece
/// fora do brief (não reprovam: a LLM corrige ou explica com `f2d:inferred`).
Future<Json> check(Workspace ws, List<String> paths) async {
  // Caminho absoluto: o agente chama da raiz do monorepo e o `dart analyze` roda de dentro do pacote; relativo, o
  // analyze não acharia o arquivo e passaria sem erro nenhum.
  final files = [for (final p in paths) File(p).absolute.path];
  // O que as tarefas do pacote esperam (gravado pelo `resolve`); sem tarefa, só as dicas de valor solto sem sugestão.
  final tokens = <String, List<Json>>{};
  final expected = <String, Json>{};
  final tasks = Directory(ws.tasks);
  for (final f in tasks.existsSync() ? tasks.listSync().whereType<Directory>() : const <Directory>[]) {
    final file = File('${f.path}/check.json');
    if (!file.existsSync()) continue;
    final c = jsonDecode(file.readAsStringSync()) as Json;
    for (final MapEntry(:key, :value) in ((c['tokens'] as Json?) ?? const {}).entries) {
      tokens.putIfAbsent(key, () => (value as List).cast<Json>());
    }
    for (final MapEntry(:key, :value) in ((c['files'] as Json?) ?? const {}).entries) {
      expected['${Directory(ws.app).resolveSymbolicLinksSync()}/$key'] = value as Json;
    }
  }
  final hints = [
    for (final path in files)
      ...hintsFor(
        path,
        File(path).readAsStringSync(),
        expect: expected[File(path).resolveSymbolicLinksSync()], // caminho real dos dois lados
        tokens: tokens,
      ),
  ];
  final markers = <Json>[];
  for (final path in files) {
    final lines = File(path).readAsLinesSync();
    for (var n = 0; n < lines.length; n++) {
      for (final m in RegExp(
        r'f2d:(guided|gap|sketch|local|placeholder|inferred)\b|TODO\(f2d\)',
      ).allMatches(lines[n])) {
        markers.add({'file': path, 'line': n + 1, 'marker': m[1] ?? 'todo', 'text': lines[n].trim()});
      }
    }
  }
  ensurePubGet(ws.app);
  final analyze = await Process.run('dart', ['analyze', '--format=machine', ...files], workingDirectory: ws.app);
  final issues = [
    for (final line in '${analyze.stdout}\n${analyze.stderr}'.split('\n'))
      if (line.split('|') case [
        final severity,
        _,
        final code,
        final file,
        final row,
        _,
        _,
        ...final message,
      ] when const {'ERROR', 'WARNING', 'INFO'}.contains(severity))
        {
          'severity': severity.toLowerCase(),
          'code': code.toLowerCase(),
          'file': file,
          'line': int.parse(row),
          'message': message.join('|'),
        },
  ];
  final blocking = [
    ...markers.where((m) => _blocking.contains(m['marker'])),
    ...issues.where((i) => i['severity'] != 'info'),
  ];
  return {
    'ok': blocking.isEmpty,
    'blocking': blocking.length,
    'markers': markers,
    'analyze': issues,
    'inferred': markers.where((m) => m['marker'] == 'inferred').length,
    'placeholders': markers.where((m) => m['marker'] == 'placeholder').length,
    'todos': markers.where((m) => m['marker'] == 'todo').length,
    'hints': hints,
  };
}

/// Grava o retrato do DS (key e nome de cada componente) no pacote de mapeamentos, a partir de exports do plugin em
/// modo biblioteca: um por página; exportar a mesma página de novo substitui a anterior. Sem [files], o
/// `figma2dart-library-*.zip` mais novo da pasta de exports.
Json library(Workspace ws, List<String> files) {
  final m = ws.mappings() ?? (throw ResolveError('Pacote de mapeamentos não encontrado: rode `figma2dart doctor`.'));
  if (files.isEmpty) {
    final newest = ws.exports().where((f) => f.uri.pathSegments.last.startsWith('figma2dart-library-')).firstOrNull;
    files = [newest?.path ?? (throw ResolveError('Nenhum figma2dart-library-*.zip em ${ws.exportsDir}.'))];
  }
  final file = File('${m.path}/$libraryFile');
  final snapshot = file.existsSync() ? jsonDecode(file.readAsStringSync()) as Json : <String, Object?>{};
  final pages = (snapshot['pages'] as Map?)?.cast<String, Object?>() ?? {};
  final updated = <String, int>{};
  for (final path in files) {
    final ir = Export.read(path).ir;
    if (ir['kind'] != 'library') {
      throw ResolveError(
        '$path é um export de ${ir['kind']}, não de biblioteca: no plugin, exporte a página do DS sem seleção.',
      );
    }
    final source = ir['source'] as Json;
    final page = '${source['fileName']} / ${source['pageName']}';
    final components = {
      for (final c in (ir['components'] as List).cast<Json>()) c['key'] as String: c['name'] as String,
    };
    pages[page] = {'fileKey': source['fileKey'], 'exportedAt': source['exportedAt'], 'components': components};
    updated[page] = components.length;
  }
  file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'pages': pages})}\n');
  return {
    'file': file.path,
    'updated': updated,
    'components': libraryKeys({'pages': pages}).length,
  };
}

/// Liga o componente [key] do Figma a um widget do app que já existe ([target]: `arquivo.dart` ou
/// `arquivo.dart#Classe`): escreve o `@FigmaLocal` em `<connect>/` do pacote do widget e põe o `figma_connect` nas
/// dev_dependencies dele, se faltar. Daí em diante o `resolve` manda montar o widget em vez de construir outro.
Future<Json> link(Workspace ws, String key, String target, {String? name}) async {
  // A key curta do placeholder (`key 26729128`) seria gravada e nunca casaria no `resolve`, sem aviso.
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(key)) {
    throw ResolveError(
      'Key "$key" incompleta: use a key inteira do componente (40 caracteres), a do `components[].key` do '
      '`resolve --json` ou do cabeçalho do brief de construção.',
    );
  }
  final [path, ...rest] = target.split('#');
  if (!File(path).existsSync()) throw ResolveError('$path não existe.');
  // Caminho real dos dois lados: com link simbólico ou `..` no caminho, o arquivo não "começaria" com o pacote.
  final widgetFile = File(File(path).resolveSymbolicLinksSync());
  final package = Directory(Workspace.find(widgetFile.parent.path).app).resolveSymbolicLinksSync();
  if (ws.dsDirs().contains(package)) {
    throw ResolveError('$path é do DS: componente do DS se mapeia no pacote de mapeamentos, não com `link`.');
  }
  // O `resolve` só lê `figma/connect/` do pacote da tela e das dependências diretas dele.
  if (!ws.localPackages().map((d) => Directory(d).resolveSymbolicLinksSync()).contains(package)) {
    throw ResolveError(
      '$path é do pacote $package, que não é o pacote da tela (${ws.app}) nem dependência direta dele: o `resolve` '
      'não leria a anotação. Adicione a dependência ou use um widget de um desses pacotes.',
    );
  }
  final lib = '$package/lib/';
  if (!widgetFile.path.startsWith(lib)) throw ResolveError('$path está fora de lib/: não dá para importar.');
  final pubspec = File('$package/pubspec.yaml').readAsStringSync();
  final import = 'package:${(loadYaml(pubspec) as Map)['name']}/${widgetFile.path.substring(lib.length)}';
  final classes = [
    for (final c in RegExp(
      r'^\s*(?:(?:abstract|base|final|sealed|interface)\s+)*class\s+([A-Z]\w*)',
      multiLine: true,
    ).allMatches(widgetFile.readAsStringSync()))
      c[1]!,
  ];
  final cls = rest.firstOrNull ?? (classes.length == 1 ? classes.single : null);
  if (cls == null || !classes.contains(cls)) {
    throw ResolveError('Diga qual classe de $path liga ao Figma (arquivo.dart#Classe): ${classes.join(', ')}.');
  }

  if (ws.library()?[key] case final dsName?) {
    throw ResolveError('A key $key é do DS ($dsName): não se liga a widget do app.');
  }

  final out = File('$package/${ws.connect}/${snakeCase(cls)}.figma.dart');
  if (out.existsSync()) {
    if (out.readAsStringSync().contains("key: '$key'")) return {'file': out.path, 'import': import, 'written': false};
    throw ResolveError('${out.path} já existe com outra key: confira antes de sobrescrever.');
  }
  out
    ..createSync(recursive: true)
    ..writeAsStringSync('''
// Liga o componente "${name ?? cls}" do Figma ao widget do app (escrito por `figma2dart link`).
${(["import 'package:figma_connect/figma_connect.dart';", "import '$import';"]..sort()).join('\n')}

@FigmaLocal(key: '$key', name: '${(name ?? cls).replaceAll("'", r"\'")}')
typedef ${cls}Figma = $cls;
''');

  final added = ensureFigmaConnect(ws, package);
  return {
    'file': out.path,
    'import': import,
    'class': cls,
    'written': true,
    if (added != null) 'devDependency': added,
  };
}

/// `pub add` do `figma_connect` como dev_dependency de [package] (o `@FigmaLocal` do `link` e a captura do `review`),
/// pelo mesmo caminho (ou versão) que o pacote de mapeamentos usa. Devolve o que foi adicionado; null se já tinha.
String? ensureFigmaConnect(Workspace ws, String package) =>
    RegExp(r'^\s+figma_connect:', multiLine: true).hasMatch(File('$package/pubspec.yaml').readAsStringSync())
    ? null
    : addFigmaConnect(ws, package);

String addFigmaConnect(Workspace ws, String package) {
  final m = ws.mappings() ?? (throw ResolveError('Pacote de mapeamentos não encontrado: rode `figma2dart doctor`.'));
  final dep =
      ((loadYaml(File('${m.path}/pubspec.yaml').readAsStringSync()) as Map)['dependencies'] as Map?)?['figma_connect'];
  final descriptor = switch (dep) {
    {'path': final String path} =>
      'dev:figma_connect:${jsonEncode({'path': _relative(_absolute(path, m.path), package)})}',
    final String version => 'dev:figma_connect:$version',
    _ => throw ResolveError('${m.path}/pubspec.yaml não depende do figma_connect.'),
  };
  final tool = RegExp(r'sdk:\s*flutter\b').hasMatch(File('$package/pubspec.yaml').readAsStringSync())
      ? 'flutter'
      : 'dart';
  final r = Process.runSync(
    tool,
    ['pub', 'add', descriptor],
    workingDirectory: package,
    runInShell: Platform.isWindows,
  );
  stderr
    ..write(r.stdout)
    ..write(r.stderr);
  if (r.exitCode != 0) throw ResolveError('`$tool pub add $descriptor` falhou em $package (saída no stderr).');
  return descriptor;
}

String _absolute(String path, String base) => Directory(
  File(path.startsWith('/') ? path : '$base/$path').absolute.uri.normalizePath().toFilePath(),
).resolveSymbolicLinksSync();

/// Caminho de [to] a partir de [from] (as duas pastas absolutas).
String _relative(String to, String from) {
  final a = to.split('/').where((p) => p.isNotEmpty).toList();
  final b = from.split('/').where((p) => p.isNotEmpty).toList();
  var common = 0;
  while (common < a.length && common < b.length && a[common] == b[common]) {
    common++;
  }
  return [for (var i = common; i < b.length; i++) '..', ...a.skip(common)].join('/');
}

/// Pacotes do repositório cujo caminho ou nome contém [query] (todos sem ela), para o agente achar onde a tela vai.
/// `ds`: o pacote depende direto de um pacote do DS (null quando o pacote de mapeamentos não foi achado).
Json packages(Workspace ws, String? query) {
  final repo = ws.repo ?? (throw ResolveError('`packages` usa o índice do git: rode de dentro do repositório.'));
  final ds = ws.dsPackages();
  final q = query?.toLowerCase();
  final found = <Json>[];
  for (final file in ws.tracked('**/pubspec.yaml')) {
    final dir = File(file).parent.path;
    final relative = dir == repo ? '.' : dir.substring(repo.length + 1);
    if (relative.split('/').contains('example')) continue;
    final Object? yaml;
    try {
      yaml = loadYaml(File(file).readAsStringSync());
    } on YamlException {
      continue;
    }
    if (yaml is! Map) continue;
    final name = '${yaml['name']}';
    if (q != null && !relative.toLowerCase().contains(q) && !name.toLowerCase().contains(q)) continue;
    final deps = (yaml['dependencies'] as Map?)?.keys.toSet() ?? const {};
    found.add({'name': name, 'path': dir, 'relative': relative, 'ds': ds?.any(deps.contains)});
  }
  found.sort((a, b) {
    final byDs = (b['ds'] == true ? 1 : 0) - (a['ds'] == true ? 1 : 0);
    return byDs != 0 ? byDs : (a['relative'] as String).compareTo(b['relative'] as String);
  });
  return {'query': query, 'total': found.length, 'packages': found.take(30).toList()};
}

/// Põe o comando `figma2dart` no PATH (`~/.pub-cache/bin`): uma cópia de `tool/figma2dart`, que roda a CLI do
/// repositório git de onde for chamado e, fora dele, a deste código. Rodar de novo só reescreve o arquivo.
Future<Json> setup({String? bin}) async {
  final cli = Directory.fromUri(await _package()).path.replaceFirst(RegExp(r'/$'), '');
  final dir = bin ?? '${Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache'}/bin';
  final script = File('$cli/tool/figma2dart').readAsStringSync();
  final target = File('$dir/figma2dart')
    ..createSync(recursive: true)
    ..writeAsStringSync(script.replaceFirst(RegExp(r'^fallback=.*$', multiLine: true), "fallback='$cli'"));
  await Process.run('chmod', ['+x', target.path]);
  return {
    'installed': target.path,
    'fallback': cli,
    'inPath': (Platform.environment['PATH'] ?? '').split(':').contains(dir),
  };
}

/// Prepara o app: `figma2dart.yaml`, `.figma2dart/` no `.gitignore`, agente e skills do Copilot. [force] atualiza
/// agente e skills; o config é do app e nunca é sobrescrito.
Future<Json> init(Workspace ws, {bool force = false}) async {
  final written = <String>[];
  final skipped = <String>[];
  void write(String relative, String content, {bool overwrite = false}) {
    final file = File('${ws.app}/$relative');
    if (file.existsSync() && !overwrite) {
      skipped.add(relative);
      return;
    }
    file
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    written.add(relative);
  }

  write(Workspace.configName, _configTemplate);
  final gitignore = File('${ws.app}/.gitignore');
  final ignored = gitignore.existsSync() ? gitignore.readAsStringSync() : '';
  if (!ignored.split('\n').contains('.figma2dart/')) {
    gitignore.writeAsStringSync('${ignored.isEmpty || ignored.endsWith('\n') ? ignored : '$ignored\n'}.figma2dart/\n');
    written.add('.gitignore');
  }

  final templates = await _templates();
  for (final file in templates.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.substring(templates.path.length + 1);
    // agents/x.agent.md → .github/agents/; skills/x/SKILL.md → .agents/skills/ (Copilot e opencode leem os dois).
    final target = relative.startsWith('agents/') ? '.github/$relative' : '.agents/$relative';
    write(target, file.readAsStringSync(), overwrite: force);
  }
  return {'app': ws.app, 'written': written, 'skipped': skipped, 'force': force};
}

/// `agent/` do pacote figma2dart: a fonte do agente e das skills que o `init` instala.
Future<Directory> _templates() async => Directory.fromUri((await _package()).resolve('agent'));

/// Pasta do pacote figma2dart (com `/` no fim).
Future<Uri> _package() async {
  final lib = await Isolate.resolvePackageUri(Uri.parse('package:figma2dart/src/commands.dart'));
  // shortcut: só funciona rodando do código-fonte (dart run); embutir os arquivos quando a CLI for compilada.
  if (lib == null) throw ResolveError('Não achei o pacote figma2dart: rode a CLI a partir do código-fonte.');
  return lib.resolve('../../');
}

const _configTemplate = '''
# figma2dart: onde ficam as coisas neste app. Tudo é opcional; o que faltar, `figma2dart doctor` aponta.

# Pacote com lib/connect/*.figma.dart. Sem isso, a CLI procura nas dependências do app.
# mappings: ../design_system/carteira_ds_figma

# Pasta onde o plugin do Figma salva os figma2dart-*.zip (padrão: ~/Downloads).
# exports: ~/Downloads

# Pasta das telas geradas, relativa ao app. Componentes fora do DS vão em <screens>/widgets/.
# screens: lib/features/minha_feature
''';
