import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'mappings.dart';

/// O pacote onde a tela vai ser escrita e tudo que a CLI descobre a partir dele, para ninguém passar caminho à mão:
/// config, pacote de mapeamentos, pasta dos exports do plugin, pasta das telas e das tarefas. Num monorepo, o config
/// do repositório (o `figma_to_dart.yaml` com `mappings:`) é achado pelo índice do git, esteja onde estiver.
class Workspace {
  Workspace._(this.app, this.repo, this.configs);

  /// Pacote alvo: a pasta com `pubspec.yaml` mais próxima de onde a CLI foi chamada, ou a de `--package`.
  final String app;

  /// Raiz do repositório git; null fora de um.
  final String? repo;

  /// Configs lidos, do menos para o mais próximo do pacote (o do repo, o do pacote e o local, de quem usa):
  /// arquivo → conteúdo.
  final Map<String, Map<String, Object?>> configs;

  static const configName = 'figma_to_dart.yaml';

  /// O nome antigo do config: a CLI não lê mais, e o `doctor` pede para renomear.
  static const legacyConfigName = 'figma2dart.yaml';

  /// Configs com o nome antigo ([legacyConfigName]) no repositório ou no pacote.
  List<String> get legacyConfigs => {
    if (repo case final repo?) ..._tracked(repo, '**/$legacyConfigName'),
    if (File('$app/$legacyConfigName').existsSync()) '$app/$legacyConfigName',
  }.toList();

  /// [package] escolhe o pacote alvo; sem ele, o mais próximo de [from], subindo. O `pubspec.yaml` da raiz do repo
  /// sem `lib/` (o do melos) não conta como pacote. Com [anywhere] (comandos que não escrevem num pacote, como
  /// `packages`), sem pacote vale a pasta de [from].
  static Workspace find(String from, {String? package, bool anywhere = false}) {
    final start = Directory(package ?? from).absolute.path;
    final repo = _git(Directory(start).existsSync() ? start : from, ['rev-parse', '--show-toplevel'])?.trim();
    String app;
    try {
      app = package != null ? _package(start) : _nearest(start, repo);
    } on ResolveError {
      if (!anywhere) rethrow;
      app = start;
    }
    final configs = <String, Map<String, Object?>>{};
    if (repo != null) {
      final withMappings = [
        for (final file in _tracked(repo, '**/$configName'))
          if (_read(file) case final config when config.containsKey('mappings')) (file, config),
      ];
      if (withMappings.length > 1) {
        throw ResolveError(
          'Mais de um $configName com `mappings:` no repositório: ${withMappings.map((c) => c.$1).join(', ')}. '
          'Deixe `mappings:` só no config do repositório.',
        );
      }
      if (withMappings.singleOrNull case (final file, final config)) configs[file] = config;
    }
    final own = File('$app/$configName');
    // O do pacote pode ser o próprio config do repo (já lido, com o caminho real que o git devolve).
    if (own.existsSync() && !configs.containsKey(_real(own.path))) configs[own.path] = _read(own.path);
    final local = File('$app/.figma2dart/$localConfig');
    if (local.existsSync()) configs[local.path] = _read(local.path);
    return Workspace._(app, repo, configs);
  }

  /// O que é só de quem usa, neste pacote (tarefas e escolhas como a pasta das telas): fora do git, porque a pasta
  /// se ignora sozinha ([ensureLocal]).
  String get local => '$app/.figma2dart';

  String get tasks => '$local/tasks';

  /// Config local, em [local]: o mais próximo de todos; não vai para o git.
  static const localConfig = 'local.yaml';

  /// Cria [local] com um `.gitignore` que ignora tudo: num monorepo, nenhum pacote precisa listar a pasta.
  void ensureLocal() {
    final ignore = File('$local/.gitignore');
    if (!ignore.existsSync()) (ignore..createSync(recursive: true)).writeAsStringSync('*\n');
  }

  /// Pasta das telas geradas (`screens:`), relativa ao pacote; null enquanto ninguém decidiu.
  String? get screens => _value('screens')?.value as String?;

  /// Guarda [dir] como a pasta das telas deste pacote só para quem usa (`.figma2dart/local.yaml`), sem criar config
  /// versionado: num monorepo, cada pacote tem a sua. Absoluta ou relativa ao pacote; fora dele é erro.
  void rememberScreens(String dir) {
    final full = File(dir.startsWith('/') ? dir : '$app/$dir').absolute.uri.normalizePath().toFilePath();
    final relative = full.startsWith('$app/') ? full.substring(app.length + 1).replaceFirst(RegExp(r'/$'), '') : '';
    if (relative.isEmpty) throw ResolveError('A pasta das telas ($dir) precisa ser uma pasta dentro de $app.');
    ensureLocal();
    final file = File('$local/$localConfig');
    file.writeAsStringSync('screens: ${jsonEncode(relative)}\n');
    configs[file.path] = {'screens': relative};
  }

  /// Pacote de mapeamentos, sem carregar: `mappings:` no config, a dependência do pacote que tem
  /// `lib/figma_policy.dart` ou, no repositório, o único pacote com ela. [packageConfig] é
  /// o do pacote alvo quando os mapeamentos vieram das dependências dele (é com ele que os imports resolvem).
  ({String path, String? packageConfig, String via})? mappings() => _mappings;

  // Calculado uma vez: várias consultas por comando (DS, pacotes locais, retrato) e o Workspace não muda.
  late final _mappings = _findMappings();

  ({String path, String? packageConfig, String via})? _findMappings() {
    if (_value('mappings') case (value: final String path, :final base)) {
      return (path: _resolve(path, base), packageConfig: null, via: 'config');
    }
    final file = File('$app/.dart_tool/package_config.json');
    if (file.existsSync()) {
      final base = file.parent.uri;
      final found = [
        for (final p in ((jsonDecode(file.readAsStringSync()) as Map)['packages'] as List).cast<Map<String, Object?>>())
          if (_dir(base, p['rootUri']! as String) case final dir when dir != app && _hasMappings(dir)) dir,
      ];
      if (found.length > 1) {
        throw ResolveError(
          'Mais de um pacote de mapeamentos nas dependências: ${found.join(', ')}. Escolha um com '
          '`mappings:` no $configName.',
        );
      }
      if (found.isNotEmpty) return (path: found.single, packageConfig: file.path, via: 'dependência do pacote');
    }
    if (repo case final repo?) {
      final policies = [for (final f in _tracked(repo, '**/lib/figma_policy.dart')) File(f).parent.parent.path];
      if (policies.length == 1) return (path: policies.single, packageConfig: null, via: 'repositório');
    }
    return null;
  }

  /// Os mapeamentos do DS ([override]: outro pacote, como `--mappings`) mais os `@FigmaLocal` do pacote alvo e das
  /// dependências por path dele.
  Future<MappingSet> loadMappingsOrFail({String? override}) async {
    final m = override != null
        ? (path: override, packageConfig: null, via: '--mappings')
        : mappings() ??
              (throw ResolveError(
                'Pacote de mapeamentos não encontrado: aponte `mappings:` no $configName do repositório (ou do '
                'pacote), ou adicione o pacote como dev_dependency.',
              ));
    if (m.packageConfig == null) ensurePubGet(m.path);
    final ds = await loadMappings(m.path, packageConfig: m.packageConfig);
    final locals = <Mapping>[];
    final warnings = <String>[];
    for (final dir in localPackages()) {
      if (!Directory('$dir/$connect').existsSync()) continue;
      try {
        ensurePubGet(dir);
      } on ResolveError catch (e) {
        warnings.add('${e.message} Os @FigmaLocal de $dir ficaram de fora.');
        continue;
      }
      final r = await loadLocalMappings(dir, connect: connect);
      locals.addAll(r.locals);
      warnings.addAll(r.warnings);
    }
    return ds.withLocal(locals, warnings: warnings);
  }

  /// Onde cada classe de [names] está declarada no `lib/` dos [localPackages] (a primeira achada).
  Map<String, String> findClasses(Set<String> names) {
    if (names.isEmpty) return const {};
    final declaration = RegExp(
      '^\\s*(?:(?:abstract|base|final|sealed|interface)\\s+)*class\\s+(${names.map(RegExp.escape).join('|')})\\b',
      multiLine: true,
    );
    final found = <String, String>{};
    for (final dir in localPackages()) {
      final lib = Directory('$dir/lib');
      if (!lib.existsSync()) continue;
      for (final file in lib.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        for (final m in declaration.allMatches(file.readAsStringSync())) {
          found.putIfAbsent(m[1]!, () => file.path);
        }
      }
    }
    return found;
  }

  /// Pasta dos `@FigmaLocal` em cada pacote (`connect:` no config).
  String get connect => _value('connect')?.value as String? ?? 'figma/connect';

  /// Onde podem estar os widgets do app que a tela usa: o pacote alvo e as dependências por path dele (diretas, de
  /// `dependencies` e `dev_dependencies`), menos os pacotes do DS.
  List<String> localPackages() {
    final pubspec = loadYaml(File('$app/pubspec.yaml').readAsStringSync());
    final ds = dsDirs();
    return [
      app,
      for (final section in ['dependencies', 'dev_dependencies'])
        for (final dep in ((pubspec is Map ? pubspec[section] : null) as Map? ?? const {}).values)
          if (dep case {
            'path': final String path,
          } when File('${_resolve(path, app)}/pubspec.yaml').existsSync() && !ds.contains(_real(_resolve(path, app))))
            _resolve(path, app),
    ];
  }

  /// Nomes dos pacotes do DS: as dependências por path do pacote de mapeamentos, menos o `figma_connect`.
  Set<String>? dsPackages() => _ds()?.keys.toSet();

  /// O retrato do DS (`figma_library.json` do pacote de mapeamentos), sem carregar os mapeamentos; null sem ele.
  Map<String, String>? library() {
    final file = File('${mappings()?.path}/$libraryFile');
    return mappings() != null && file.existsSync()
        ? libraryKeys(jsonDecode(file.readAsStringSync()) as Map<String, Object?>)
        : null;
  }

  /// Pastas do DS (caminho real): o pacote de mapeamentos e os pacotes do DS. Widget daqui não é do app.
  Set<String> dsDirs() => switch ((mappings(), _ds())) {
    (final m?, final ds?) => {_real(m.path), ...ds.values},
    _ => const {},
  };

  /// Pacotes do DS, nome → pasta real.
  Map<String, String>? _ds() {
    final m = mappings();
    if (m == null) return null;
    final deps = (loadYaml(File('${m.path}/pubspec.yaml').readAsStringSync()) as Map)['dependencies'] as Map?;
    return {
      for (final MapEntry(:key, :value) in (deps ?? const {}).entries)
        if (value case {'path': final String path} when key != 'figma_connect')
          key as String: _real(_resolve(path, m.path)),
    };
  }

  /// Arquivos versionados do repositório que casam com [glob] (pelo índice do git: não varre o disco).
  List<String> tracked(String glob) => repo == null ? const [] : _tracked(repo!, glob);

  /// Pasta onde o plugin salva os exports (`exports:` no config; padrão: Downloads).
  String get exportsDir => switch (_value('exports')) {
    (value: final String path, :final base) => _resolve(path, base),
    _ => _resolve('~/Downloads', app),
  };

  /// Exports do plugin (`figma2dart-*.zip`), o mais novo primeiro.
  List<File> exports() {
    final dir = Directory(exportsDir);
    if (!dir.existsSync()) return [];
    return dir.listSync().whereType<File>().where((f) {
      final name = f.uri.pathSegments.last;
      return name.startsWith('figma2dart-') && name.toLowerCase().endsWith('.zip');
    }).toList()..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  /// Valor de [key] no config mais próximo do pacote, com a pasta do arquivo (base dos caminhos relativos).
  ({Object value, String base})? _value(String key) {
    for (final MapEntry(key: file, value: config) in configs.entries.toList().reversed) {
      if (config[key] case final value?) return (value: value, base: File(file).parent.path);
    }
    return null;
  }

  /// Caminho do config: `~` é a home; relativo é a partir de [base].
  static String _resolve(String path, String base) {
    if (path.startsWith('~/')) return '${Platform.environment['HOME']}${path.substring(1)}';
    final full = path.startsWith('/') ? path : '$base/$path';
    return File(full).absolute.uri.normalizePath().toFilePath(); // sem `x/../`
  }

  static Map<String, Object?> _read(String file) {
    final yaml = loadYaml(File(file).readAsStringSync());
    return yaml is Map ? Map<String, Object?>.from(yaml) : {};
  }

  static String _package(String dir) {
    if (!File('$dir/pubspec.yaml').existsSync()) throw ResolveError('--package $dir: não tem pubspec.yaml.');
    return dir;
  }

  static String _nearest(String from, String? repo) {
    for (var dir = Directory(from); ; dir = dir.parent) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        if (dir.path != repo && _real(dir.path) != repo || Directory('${dir.path}/lib').existsSync()) return dir.path;
        throw ResolveError(
          'Chamada da raiz do repositório: passe o pacote com --package (ache-o com `figma2dart packages <parte do nome>`).',
        );
      }
      if (dir.parent.path == dir.path) {
        throw ResolveError('Nenhum pubspec.yaml em $from ou acima: rode de dentro do pacote ou passe --package.');
      }
    }
  }

  /// Caminho real (o git devolve sem links simbólicos: `/tmp` → `/private/tmp` no macOS).
  static String _real(String path) => File(path).resolveSymbolicLinksSync();

  static String? _git(String dir, List<String> args) {
    try {
      final r = Process.runSync('git', args, workingDirectory: dir);
      return r.exitCode == 0 ? r.stdout as String : null;
    } on ProcessException {
      return null; // sem git: só a descoberta local
    }
  }

  static List<String> _tracked(String repo, String glob) => [
    for (final path in (_git(repo, ['ls-files', '-z', ':(glob)$glob']) ?? '').split('\x00'))
      if (path.isNotEmpty) '$repo/$path',
  ];

  /// Pasta do pacote, sem barra no fim (`rootUri` pode ou não terminar em `/`).
  static String _dir(Uri base, String rootUri) =>
      base.resolve(rootUri.endsWith('/') ? rootUri : '$rootUri/').toFilePath().replaceFirst(RegExp(r'/+$'), '');

  // Pela política, sem varrer o `lib/` de cada dependência.
  static bool _hasMappings(String dir) => File('$dir/lib/figma_policy.dart').existsSync();
}

/// `pub get` no pacote quando falta o `package_config.json` ou o `pubspec.yaml` mudou depois dele (num monorepo,
/// pacote fora do melos pode nunca ter rodado). A saída vai para o stderr: o stdout é do JSON.
void ensurePubGet(String dir) {
  final config = File('$dir/.dart_tool/package_config.json');
  final pubspec = File('$dir/pubspec.yaml');
  if (config.existsSync() && !pubspec.lastModifiedSync().isAfter(config.lastModifiedSync())) return;
  final tool = RegExp(r'sdk:\s*flutter\b').hasMatch(pubspec.readAsStringSync()) ? 'flutter' : 'dart';
  final r = Process.runSync(tool, ['pub', 'get'], workingDirectory: dir, runInShell: Platform.isWindows);
  stderr
    ..write(r.stdout)
    ..write(r.stderr);
  if (r.exitCode != 0) throw ResolveError('`$tool pub get` falhou em $dir (saída acima, no stderr).');
  // Sem mudança de dependência o pub não regrava o arquivo: sem isso, o pub get rodaria em toda chamada.
  final now = DateTime.now(); // pubspec com data no futuro (relógio, checkout) também não pode repetir o pub get
  final touched = pubspec.lastModifiedSync();
  config.setLastModifiedSync(touched.isAfter(now) ? touched : now);
}
