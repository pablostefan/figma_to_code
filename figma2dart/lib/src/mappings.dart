// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
// shortcut: a API pública não aceita package_config de fora do pacote; trocar se o analyzer expuser isso.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/byte_store.dart';

import 'tokens.dart';

/// Valor do Figma ou mapeamento que não dá para usar (prop ausente, variant sem mapeamento, mapeamento ambíguo…).
class ResolveError implements Exception {
  ResolveError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// `Doc` da anotação: `path`, ou `url` com `source` opcional (arquivo local com o mesmo conteúdo).
typedef DocRef = ({String? path, String? url, String? source, String? section, String? hint});

/// `Example` da anotação: `kind` é `code` (escrito para a LLM) ou `usage` (uso real num app).
typedef ExampleRef = ({String kind, String path, String symbol, String? repo, String? hint});

/// Uma função anotada com `@FigmaConnect`, lida do pacote de mapeamentos.
class Mapping {
  Mapping({
    required this.key,
    required this.name,
    required this.when,
    required this.kind,
    required this.coverage,
    required this.guide,
    required this.devNotes,
    required this.figmaNotes,
    required this.docs,
    required this.examples,
    required this.declaration,
    required this.widget,
    required this.file,
    required this.source,
    required this.unit,
  });

  final String key;
  final String name;
  final Map<String, String> when;

  /// Nome do valor de `FigmaKind`: `component`, `section`, `template` ou `icon`.
  final String kind;

  /// Nome do valor de `Coverage`: `complete`, `partial` ou `sketch`; `local` num `@FigmaLocal` (widget do app).
  final String coverage;
  final String? guide;

  /// Já formatadas para o brief: `[obrigatório · lint x] texto` ou `[recomendado] texto`. Inclui as regras do tipo
  /// (`KindPolicy.devNotes`) antes das do componente.
  final List<String> devNotes;

  /// `figmaNotes` `derive` e `map`, já formatadas (`ignore` não entra no brief).
  final List<String> figmaNotes;

  final List<DocRef> docs;
  final List<ExampleRef> examples;
  final String file;
  final String source;
  final CompilationUnit unit;

  /// A função anotada, ou o `typedef` no caso do `FigmaConnect.sketch` (que não tem corpo para avaliar).
  final CompilationUnitMember declaration;

  /// A classe do widget do DS: o tipo do `typedef` do sketch, ou o tipo que a função devolve.
  final InterfaceElement? widget;

  /// A função de um mapeamento `complete`/`partial`; null no sketch.
  FunctionDeclaration? get function => declaration is FunctionDeclaration ? declaration as FunctionDeclaration : null;

  String get functionName => _name(declaration);
}

/// Todos os mapeamentos de um pacote (`lib/**/*.figma.dart`), mais os `@FigmaLocal` do app.
class MappingSet {
  MappingSet(
    this.components, {
    this.root,
    this.screen,
    this.policy = const Policy(),
    this.library,
    this.warnings = const [],
  });

  /// `@FigmaLocal` que ficou de fora (não compila, key do DS ou repetida…): o componente volta a ser a construir e o
  /// agente avisa o usuário. Anotação de um time não pode travar a tela dos outros.
  final List<String> warnings;

  final List<Mapping> components;

  /// Retrato do DS (`figma_library.json`): key de cada componente da biblioteca → nome. Null sem retrato.
  final Map<String, String>? library;

  /// A instância é de um componente do DS: key no retrato; sem retrato, componente remoto (de alguma biblioteca).
  bool fromDs(Map<String, Object?> instance) => switch (library) {
    final keys? => keys.containsKey(instance['componentKey']) || keys.containsKey(instance['mainComponentKey']),
    null => instance['remote'] == true,
  };

  /// Este conjunto com os `@FigmaLocal` do app. Key do DS, de um mapeamento do DS ou repetida fica de fora, com
  /// aviso: a instância teria dois donos.
  MappingSet withLocal(List<Mapping> locals, {List<String> warnings = const []}) {
    final seen = <String, Mapping>{for (final m in components) m.key: m};
    final kept = <Mapping>[];
    final skipped = [...this.warnings, ...warnings];
    for (final m in locals) {
      final at = '${m.functionName} (${m.file})';
      if (library?[m.key] case final name?) {
        skipped.add('$at: a key ${m.key} é do DS ($name); mapeie no pacote de mapeamentos do DS.');
      } else if (seen[m.key] case final other?) {
        skipped.add('$at: a key ${m.key} já tem mapeamento em ${other.file}.');
      } else {
        seen[m.key] = m;
        kept.add(m);
      }
    }
    return MappingSet(
      [...components, ...kept],
      root: root,
      screen: screen,
      policy: policy,
      library: library,
      warnings: skipped,
    );
  }

  /// Código da função `@FigmaScreen` (o esqueleto de toda tela), se o pacote tiver.
  final String? screen;
  final Policy policy;

  /// Pasta do pacote; docs e exemplos são procurados a partir dela. Null: brief sem docs.
  final String? root;

  /// O mapeamento da instância: primeiro pela key exata da variant, depois pela do set. Entre os candidatos, os que
  /// têm `when` compatível com as props; vence o mais específico. Empate é erro: a escolha seria por acaso.
  Mapping? find({required String componentKey, String? mainComponentKey, required Map<String, Object?> props}) {
    for (final key in [if (mainComponentKey != null) mainComponentKey, componentKey]) {
      final candidates =
          components.where((m) => m.key == key && m.when.entries.every((w) => props[w.key] == w.value)).toList()
            ..sort((a, b) => b.when.length.compareTo(a.when.length));
      if (candidates.length > 1 && candidates[0].when.length == candidates[1].when.length) {
        throw ResolveError(
          '${candidates[0].name}: dois mapeamentos servem para a mesma instância '
          '(${candidates[0].functionName} em ${candidates[0].file} e ${candidates[1].functionName} em '
          '${candidates[1].file}); diferencie com `when`.',
        );
      }
      if (candidates.isNotEmpty) return candidates.first;
    }
    return null;
  }
}

/// O que a CLI usa do `FigmaPolicy` do pacote.
class Policy {
  const Policy({this.ignored = const {}, this.icons, this.iconByKey = const {}, this.tokens});

  /// `TokenTable`: tokens do Figma → código Dart. Null: o brief fica com os nomes do Figma.
  final Tokens? tokens;

  /// Componentes só do Figma: key → motivo.
  final Map<String, String> ignored;

  /// Os ícones do DS: o enum de `IconTable.values` ou a classe de `IconTable.constants`.
  final InterfaceElement? icons;

  /// Exceções de ícone: `mainComponentKey` → nome do valor (`IconTable.byKey`).
  final Map<String, String> iconByKey;

  /// Componente que não entra na tela: prefixo `_`/`.` no nome (só do Figma) ou key em `ignored`.
  /// O prefixo não vale para componente [annotated]: um `.Icon Button / Large` (base travada, exposta dentro de um
  /// componente público) com anotação própria é do DS.
  String? ignoreReason(Map<String, Object?> instance, {bool annotated = false}) {
    if (instance['componentName'] case final String name
        when !annotated && (name.startsWith('_') || name.startsWith('.'))) {
      return 'componente só do Figma (prefixo `${name[0]}`)';
    }
    return ignored[instance['mainComponentKey']] ?? ignored[instance['componentKey']];
  }
}

/// Lê os mapeamentos de [packageDir] com o analyzer, resolvendo tipos e constantes (ex.: `key: _key`).
/// Os imports resolvem pelo [packageConfig] (o do app, quando o pacote é dependência dele) ou pelo `pub get` do
/// próprio pacote.
Future<MappingSet> loadMappings(String packageDir, {String? packageConfig}) async {
  final root = Directory(packageDir).resolveSymbolicLinksSync();
  // As anotações ficam em qualquer pasta de `lib/` (`lib/acme/components/button/`, `lib/templates/`, `lib/connect/`).
  final lib = Directory('$root/lib');
  if (!lib.existsSync()) throw ArgumentError('$root não tem lib/');
  final files =
      lib
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.figma.dart'))
          .toList()
        ..sort();
  // A política fica em `lib/figma_policy.dart` (docs/ARQUITETURA.md §3); é lida antes, porque acrescenta regras aos mapeamentos.
  if (File('$root/lib/figma_policy.dart').existsSync()) files.insert(0, '$root/lib/figma_policy.dart');

  final units = await _analyze(root, files, packageConfig);

  var policy = const Policy();
  var kindNotes = <String, List<String>>{};
  for (final unit in units) {
    for (final variable in unit.unit.declarations.whereType<TopLevelVariableDeclaration>()) {
      for (final v in variable.variables.variables) {
        final value = v.declaredElement?.computeConstantValue();
        if (value?.type?.element?.name == 'FigmaPolicy') (policy, kindNotes) = _policy(value!);
      }
    }
  }

  final components = <Mapping>[];
  String? screen;
  for (final result in units) {
    for (final declaration in result.unit.declarations.whereType<CompilationUnitMember>()) {
      for (final annotation in declaration.metadata) {
        final value = annotation.elementAnnotation?.computeConstantValue();
        switch (value?.type?.element?.name) {
          case 'FigmaConnect':
            components.add(_mapping(value!, declaration, result.path, result, kindNotes));
          case 'FigmaScreen':
            screen = result.content.substring(declaration.offset, declaration.end);
          case 'FigmaLocal':
            throw StateError(
              '${result.path}: @FigmaLocal é de componente do app; fica em figma/connect/ do pacote dele.',
            );
        }
      }
    }
  }
  final snapshot = File('$root/$libraryFile');
  return MappingSet(
    components,
    root: root,
    screen: screen,
    policy: policy,
    library: snapshot.existsSync()
        ? libraryKeys(jsonDecode(snapshot.readAsStringSync()) as Map<String, Object?>)
        : null,
  );
}

/// Retrato do DS no pacote de mapeamentos, escrito por `figma2dart library`.
const libraryFile = 'figma_library.json';

/// Key → nome de todos os componentes do retrato (todas as páginas exportadas).
Map<String, String> libraryKeys(Map<String, Object?> snapshot) => {
  for (final page in ((snapshot['pages'] as Map?) ?? const {}).values)
    ...(((page as Map)['components'] as Map?) ?? const {}).cast<String, String>(),
};

/// Os `@FigmaLocal` de [dir] (`<connect>/**/*.figma.dart`), resolvidos com o `package_config` do próprio pacote.
/// Arquivo que não compila ou anotação no lugar errado fica de fora, em `warnings`.
Future<({List<Mapping> locals, List<String> warnings})> loadLocalMappings(
  String dir, {
  String connect = 'figma/connect',
}) async {
  final root = Directory(dir).resolveSymbolicLinksSync();
  final folder = Directory('$root/$connect');
  final warnings = <String>[];
  if (!folder.existsSync()) return (locals: const <Mapping>[], warnings: warnings);
  final files =
      folder
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.figma.dart'))
          .toList()
        ..sort();
  final locals = <Mapping>[];
  for (final result in await _analyze(root, files, '$root/.dart_tool/package_config.json', skip: warnings.add)) {
    for (final declaration in result.unit.declarations.whereType<CompilationUnitMember>()) {
      for (final annotation in declaration.metadata) {
        final value = annotation.elementAnnotation?.computeConstantValue();
        switch (value?.type?.element?.name) {
          case 'FigmaLocal':
            try {
              locals.add(_local(value!, declaration, result));
            } on StateError catch (e) {
              warnings.add(e.message);
            }
          case 'FigmaConnect' || 'FigmaScreen':
            warnings.add('${result.path}: mapeamento do DS fica no pacote de mapeamentos (lib/), não no app.');
        }
      }
    }
  }
  return (locals: locals, warnings: warnings);
}

Mapping _local(DartObject value, CompilationUnitMember declaration, ResolvedUnitResult result) {
  final widget = switch (declaration) {
    GenericTypeAlias(:final type) => type.type?.element,
    _ => null,
  };
  if (widget is! InterfaceElement) {
    throw StateError(
      '${_name(declaration)} (${result.path}): @FigmaLocal anota um typedef para a classe do widget '
      '(typedef X = MeuWidget;).',
    );
  }
  return Mapping(
    key: _str(value, 'key')!,
    name: _str(value, 'name')!,
    when: const {},
    kind: 'component',
    coverage: 'local',
    guide: _str(value, 'guide'),
    devNotes: const [],
    figmaNotes: const [],
    docs: const [],
    examples: const [],
    declaration: declaration,
    widget: widget,
    file: result.path,
    source: result.content,
    unit: result.unit,
  );
}

/// Cache das análises de uma execução: o DS e cada pacote com `@FigmaLocal` têm o próprio package_config, mas o SDK
/// do Flutter é o mesmo; sem cache comum, cada pacote o analisa de novo (~4 s).
final _byteStore = MemoryByteStore();

/// Analisa [files] de [root] resolvendo tipos. Arquivo que não compila é erro (o brief sairia errado); com [skip],
/// vai para ele e o arquivo fica de fora.
Future<List<ResolvedUnitResult>> _analyze(
  String root,
  List<String> files,
  String? packageConfig, {
  void Function(String problem)? skip,
}) async {
  final session = AnalysisContextCollectionImpl(
    byteStore: _byteStore,
    includedPaths: [root],
    packagesFile: packageConfig == null ? null : File(packageConfig).absolute.uri.normalizePath().toFilePath(),
  ).contextFor(root).currentSession;
  final units = <ResolvedUnitResult>[];
  for (final file in files) {
    final result = await session.getResolvedUnit(file);
    final errors = result is ResolvedUnitResult
        ? result.errors.where((d) => d.severity == Severity.error).toList()
        : null;
    final problem = switch (errors) {
      null => 'Não foi possível analisar $file',
      [final first, ...] => '$file não compila: ${first.message}',
      [] => null,
    };
    if (problem == null) {
      units.add(result as ResolvedUnitResult);
    } else if (skip != null) {
      skip(problem);
    } else {
      throw StateError(problem);
    }
  }
  return units;
}

/// `FigmaPolicy` → o que a CLI usa, e as regras de cada tipo já formatadas.
(Policy, Map<String, List<String>>) _policy(DartObject value) {
  final icons = value.getField('icons');
  final values = icons?.getField('values')?.toListValue() ?? const [];
  return (
    Policy(
      ignored: {
        for (final MapEntry(:key, value: v) in (value.getField('ignored')?.toMapValue() ?? const {}).entries)
          key!.toStringValue()!: v!.toStringValue()!,
      },
      icons: switch ((values.firstOrNull?.type?.element, icons?.getField('constants')?.toTypeValue()?.element)) {
        (final EnumElement e, _) => e,
        (_, final InterfaceElement c) => c,
        _ => null,
      },
      iconByKey: {
        for (final MapEntry(:key, value: v) in (icons?.getField('byKey')?.toMapValue() ?? const {}).entries)
          key!.toStringValue()!: v!.variable!.name,
      },
      tokens: Tokens.read(value.getField('tokens')),
    ),
    {
      for (final MapEntry(:key, value: kind) in (value.getField('kinds')?.toMapValue() ?? const {}).entries)
        key!.variable!.name: [
          for (final note in kind?.getField('devNotes')?.toListValue() ?? const <DartObject>[]) _devNote(note),
        ],
    },
  );
}

String? _str(DartObject? o, String field) => o?.getField(field)?.toStringValue();

String _devNote(DartObject note) => switch (note.type?.element?.name) {
  'MustNote' => [
    '[obrigatório',
    if (_str(note, 'lint') case final lint?) ' · lint $lint',
    '] ${_str(note, 'rule')}',
  ].join(),
  _ => '[recomendado] ${_str(note, 'rule')}',
};

/// Valor de `FigmaNote.map` como literal Dart: texto entre aspas, enum como `Tipo.valor`.
String _literal(DartObject? o) {
  if (o == null || o.isNull) return 'null';
  if (o.toStringValue() case final s?) return "'$s'";
  if (o.variable case final v?) return '${o.type?.element?.name}.${v.name}';
  return o.toBoolValue()?.toString() ?? o.toIntValue()?.toString() ?? o.toDoubleValue()?.toString() ?? '$o';
}

String _name(CompilationUnitMember d) => switch (d) {
  FunctionDeclaration(:final name) || TypeAlias(:final name) => name.lexeme,
  _ => '$d',
};

Mapping _mapping(
  DartObject value,
  CompilationUnitMember declaration,
  String file,
  ResolvedUnitResult result,
  Map<String, List<String>> kindNotes,
) {
  final kind = value.getField('kind')?.variable?.name ?? 'component';
  final coverage = value.getField('coverage')?.variable?.name ?? 'complete';
  final at = '${_name(declaration)} ($file)';
  // Sketch só liga o componente à classe do DS; os outros níveis precisam do corpo para avaliar.
  final widget = switch ((coverage, declaration)) {
    ('sketch', GenericTypeAlias(:final type)) => type.type?.element,
    ('sketch', _) => throw StateError(
      '$at: FigmaConnect.sketch anota um typedef para a classe do DS (typedef X = DsWidget;), sem função.',
    ),
    (_, FunctionDeclaration(functionExpression: FunctionExpression(:final ExpressionFunctionBody body))) =>
      body.expression.staticType?.element,
    (_, FunctionDeclaration()) => null, // corpo em bloco: o resolvedor explica o erro na hora de avaliar
    _ => throw StateError('$at: @FigmaConnect anota uma função `Widget nome(FigmaProps f) => …`.'),
  };
  if (coverage == 'sketch' && widget is! InterfaceElement) {
    throw StateError('$at: o typedef do sketch precisa apontar para uma classe.');
  }
  List<DartObject> list(String field) => value.getField(field)?.toListValue() ?? const [];
  final when = <String, String>{
    for (final MapEntry(:key, value: v) in (value.getField('when')?.toMapValue() ?? const {}).entries)
      key!.toStringValue()!: v!.toStringValue()!,
  };
  final devNotes = [...?kindNotes[kind], for (final note in list('devNotes')) _devNote(note)];
  final figmaNotes = [
    for (final MapEntry(:key, value: note) in (value.getField('figmaNotes')?.toMapValue() ?? const {}).entries)
      if (switch (note?.type?.element?.name) {
            'DeriveNote' => _str(note, 'guide'),
            'MapNote' =>
              [
                    for (final MapEntry(key: from, value: to)
                        in (note!.getField('values')?.toMapValue() ?? const {}).entries)
                      '${from!.toStringValue()} → ${_literal(to)}',
                  ].join(', ') +
                  [if (_str(note, 'hint') case final h?) ' — $h'].join(),
            _ => null, // IgnoreNote: a prop não importa, não entra no brief
          }
          case final text?)
        'Figma `${key!.toStringValue()}`: $text',
  ];
  final docs = <DocRef>[
    for (final d in list('docs'))
      (
        path: _str(d, 'path'),
        url: _str(d, 'url'),
        source: _str(d, 'source'),
        section: _str(d, 'section'),
        hint: _str(d, 'hint'),
      ),
  ];
  final examples = <ExampleRef>[
    for (final e in list('examples'))
      (
        kind: e.type?.element?.name == 'CodeExample' ? 'code' : 'usage',
        path: _str(e, 'path')!,
        symbol: _str(e, 'symbol')!,
        repo: _str(e, 'repo'),
        hint: _str(e, 'hint'),
      ),
  ];
  return Mapping(
    key: _str(value, 'key')!,
    name: _str(value, 'name')!,
    when: when,
    kind: kind,
    coverage: coverage,
    guide: _str(value, 'guide'),
    devNotes: devNotes,
    figmaNotes: figmaNotes,
    docs: docs,
    examples: examples,
    declaration: declaration,
    widget: widget is InterfaceElement ? widget : null,
    file: file,
    source: result.content,
    unit: result.unit,
  );
}
