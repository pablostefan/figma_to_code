import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/components.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/review.dart';
import 'package:figma2dart/src/workspace.dart';

const _usage = '''
Uso: figma2dart <comando> [opções] [--json]   (de dentro do pacote, ou --package <pasta>)

  setup                        põe o comando figma2dart no PATH (uma vez por máquina)
  doctor                       onde está cada coisa e o que falta
  packages [<texto>]           pacotes do repositório cujo caminho ou nome contém o texto
  screens [<export.zip>]       telas do export (padrão: o figma2dart-*.zip mais novo)
  resolve [<export.zip>]       resolve uma tela e escreve a pasta da tarefa (BRIEF.md + briefs de componentes)
      --screen <nome> (repetível) --state <estado> --out <dir> --mappings <pacote>
  check <arquivo.dart>...      marcadores f2d que sobraram + dart analyze
  review --screen <tela>       revisão visual: Figma | Flutter (da captura figmaCapture), fatos e critério
  library [<export.zip>...]    grava o retrato do DS (exports do plugin em modo biblioteca) no pacote de mapeamentos
  components [<export.zip>...] componentes do DS × anotações: o que falta anotar (exports em modo biblioteca)
      --name <componente>      um componente para anotar: key, props, variantes (PNG) e instâncias de dentro
  link <key> <arquivo.dart>[#Classe] [--name <nome no Figma>]
                               liga um componente do Figma a um widget do app que já existe (@FigmaLocal)
  init [--force]               figma2dart.yaml, .gitignore, agente e skills do Copilot''';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addFlag('json', negatable: false, help: 'Saída em JSON (para o agente).')
    ..addFlag('force', negatable: false, help: 'init: atualiza agente e skills (o config nunca é sobrescrito).')
    ..addOption('package', help: 'Pacote onde a tela vai (padrão: o pubspec.yaml mais próximo).')
    ..addOption('mappings', help: 'Pacote com lib/connect/*.figma.dart (padrão: descoberto pelo app).')
    ..addMultiOption('screen', help: 'Nome da tela ou do frame no export (repita para várias).', splitCommas: false)
    ..addOption('name', help: 'link: nome do componente no Figma (padrão: o da classe); components: o componente.')
    ..addOption('state', help: 'Estado da tela (padrão: o do frame, ou o primeiro).')
    ..addOption('out', help: 'Pasta da tarefa (padrão: .figma2dart/tasks/<tela> no app).');
  // O script `tool/figma2dart` roda de dentro da pasta da CLI (cache do `dart run`); volta para onde foi chamado.
  if (Platform.environment['FIGMA2DART_CWD'] case final cwd?) Directory.current = cwd;
  var json = argv.contains('--json');
  try {
    final args = parser.parse(argv);
    final [command, ...rest] = args.rest.isEmpty ? ['help'] : args.rest;
    if (command == 'setup') {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(await setup()));
      return;
    }
    final ws = Workspace.find(Directory.current.path, package: args.option('package'), anywhere: command == 'packages');
    final Map<String, Object?> result = switch (command) {
      'doctor' => await doctor(ws),
      'packages' => packages(ws, rest.firstOrNull),
      'screens' => screens(exportFile(ws, rest.firstOrNull), library: ws.library()),
      'resolve' => await resolveTasks(
        ws,
        exportFile(ws, rest.firstOrNull),
        screens: args.multiOption('screen'),
        state: args.option('state'),
        out: args.option('out'),
        mappings: args.option('mappings'),
      ),
      'check' when rest.isNotEmpty => await check(ws, rest),
      'review' when args.multiOption('screen').length == 1 => review(ws, args.multiOption('screen').single),
      'library' => library(ws, rest),
      'components' => components(ws, rest, name: args.option('name')),
      'link' when rest.length == 2 => await link(ws, rest[0], rest[1], name: args.option('name')),
      'init' => await init(ws, force: args.flag('force')),
      _ => throw const FormatException(''),
    };
    stdout.writeln(json ? const JsonEncoder.withIndent('  ').convert(result) : _human(command, result));
    if (command == 'check' && result['ok'] == false) exitCode = 1;
  } on FormatException catch (e) {
    _fail(json, e.message.isEmpty ? _usage : '${e.message}\n$_usage', 64);
  } on ResolveError catch (e) {
    _fail(json, e.message, 1);
  } on FileSystemException catch (e) {
    _fail(json, '${e.message}: ${e.path}', 1);
  } catch (e) {
    // Pacote de mapeamentos sem lib/connect ou que não compila (ArgumentError/StateError de loadMappings).
    if (e is! ArgumentError && e is! StateError) rethrow;
    _fail(json, '${e is ArgumentError ? e.message : e}', 1);
  }
}

/// Erro em JSON vai para o stdout, para o agente ler do mesmo lugar que o resultado.
void _fail(bool json, String message, int code) {
  if (json) {
    stdout.writeln(jsonEncode({'error': message}));
  } else {
    stderr.writeln(code == 64 ? message : 'Erro: $message');
  }
  exitCode = code;
}

String _human(String command, Map<String, Object?> r) => switch (command) {
  'resolve' => _resolved(r),
  'check' =>
    '${r['ok'] == true ? 'ok' : '${r['blocking']} pendência(s)'}; ${r['inferred']} f2d:inferred, '
        '${r['placeholders']} placeholder(s), ${r['todos']} TODO(f2d), ${(r['hints'] as List).length} dica(s)',
  'components' when r['components'] is List =>
    '${r['annotated']} de ${r['total']} anotados, ${r['pending']} faltam'
        '${[for (final c in (r['components'] as List).cast<Map<String, Object?>>()) if (c['status'] == 'falta') '\n  ${c['page']} / ${c['name']}'].join()}',
  'review' when r['capture'] == false =>
    'Falta a captura. Escreva ${r['testFile']} (complete a tela), rode `flutter test ${r['testFile']}` e chame o '
        'review de novo:\n\n${r['test']}',
  'review' =>
    '${r['review']}\n'
        'fatos: ${(r['facts'] as Map).entries.map((e) => '${e.key} ${e.value}').join(', ')}; '
        '${(r['sections'] as List).length} seção(ões) recortada(s)',
  _ => const JsonEncoder.withIndent('  ').convert(r),
};

String _resolved(Map<String, Object?> r) => [
  for (final w in (r['warnings'] as List? ?? const [])) 'Aviso: $w',
  for (final t in (r['tasks'] as List).cast<Map<String, Object?>>())
    '${t['screen']}: ${(t['counts'] as Map)['mapped']} mapeadas, ${((t['counts'] as Map)['sketch'] as int) + ((t['counts'] as Map)['local'] as int)} para montar, '
        '${(t['counts'] as Map)['gap']} sem mapeamento, ${(t['counts'] as Map)['placeholder']} fora do DS, '
        '${(t['components'] as List).length} tarefas de componente, ${(t['counts'] as Map)['guided']} decisões '
        '→ ${t['brief']}',
].join('\n');
