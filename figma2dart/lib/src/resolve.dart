// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'icons.dart';
import 'mappings.dart';
import 'tokens.dart';
import 'names.dart';
import 'references.dart';

typedef Json = Map<String, Object?>;

/// Parte que exige julgamento (`f.guided`): o código usa o valor provisório e a LLM decide.
class Guided {
  Guided(this.id, this.instance, this.component, this.part, this.guide, this.figma);
  final String id;
  final String instance;
  final String component;
  final String part;
  final String guide;
  final Json figma;

  Json toJson() => {
    'id': id,
    'instance': instance,
    'component': component,
    'part': part,
    'guide': guide,
    'figma': figma,
  };
}

/// Uma instância da tela, já resolvida.
class ResolvedInstance {
  ResolvedInstance({
    required this.id,
    required this.name,
    required this.path,
    required this.component,
    required this.componentKey,
    required this.status,
    required this.code,
    this.mapping,
    this.error,
    this.guided = const [],
    this.overrides = const [],
    this.figma,
    this.bounds,
  });

  final String id;
  final String name;

  /// Camadas do Figma até a instância, a partir da tela (ex.: `form/Input`).
  final String path;
  final String component;
  final String componentKey;

  /// `mapped`: virou código. `sketch`: componente do DS que a LLM monta. `local`: widget do app que já existe
  /// (`@FigmaLocal`), a LLM monta. `gap`: componente do DS sem mapeamento. `placeholder`: fora do DS, a construir.
  final String status;
  final String code;
  final Mapping? mapping;

  /// Por que o mapeamento falhou nesta instância (variant ou ícone sem correspondência…); ela vira `gap`.
  final String? error;
  final List<String> guided;
  final List<Json> overrides;

  /// Em `sketch`, `local` e `placeholder`: props, instâncias expostas e o conteúdo de dentro (`content`, IR 1.3) da
  /// instância no Figma, para a LLM montar o resto ou construir o componente.
  final Json? figma;

  /// Caixa da instância relativa ao frame da tela (IR 1.3), para recortar o PNG da tela.
  final Json? bounds;

  Json toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'component': component,
    'key': componentKey,
    'status': status,
    if (mapping case final m?) 'mapping': {'file': m.file, 'function': m.functionName},
    if (error != null) 'error': error,
    'code': code,
    if (guided.isNotEmpty) 'guided': guided,
    if (overrides.isNotEmpty) 'overrides': overrides,
    if (figma != null) 'figma': figma,
  };
}

/// Resultado do `resolve` de uma tela: entrada do brief e, depois, do gerador.
class ResolvedScreen {
  ResolvedScreen({
    required this.screen,
    required this.state,
    required this.frameId,
    required this.instances,
    required this.guided,
    this.components = const [],
    this.used = const [],
    this.references = const {},
    this.image,
    this.imageScale = 2,
    this.tree = const {},
    this.navigation = const [],
    this.ignored = const [],
    this.skeleton,
    this.tokens,
  });

  /// Tabela de tokens do DS (os da árvore já estão em Dart); null sem tabela.
  final Tokens? tokens;

  final String screen;
  final String state;
  final String frameId;

  /// PNG da tela dentro do zip do plugin (`images/screens/…`); null no IR do MCP.
  final String? image;

  /// Pixels do PNG por unidade do Figma (o plugin exporta em 2x).
  final num imageScale;

  /// Árvore do frame no IR, para a estrutura da tela no brief.
  final Json tree;

  /// Código do `@FigmaScreen` do pacote: o esqueleto de toda tela (`s.body()` é o conteúdo).
  final String? skeleton;

  /// Instâncias puladas pela política (`ignored` ou prefixo `_`/`.`): `{path, component, reason}`.
  final List<Json> ignored;

  /// Protótipo do Figma saindo desta tela: `{trigger, node, to}`; `to` é o nome da tela de destino, `back` ou `close`.
  final List<Json> navigation;
  final List<ResolvedInstance> instances;
  final List<Guided> guided;

  /// Tarefas com brief próprio: componentes fora do DS a construir (dependências antes de quem as usa) e, depois,
  /// os sketches a montar.
  final List<ComponentTask> components;

  /// Mapeamentos usados na tela, um por componente.
  final List<Mapping> used;

  /// Docs e exemplos já recortados (markdown), pelo nome do componente: só dos que têm decisão nesta tela ou não são
  /// `complete`.
  final Map<String, String> references;

  Json toJson() => {
    'screen': screen,
    'state': state,
    'frameId': frameId,
    if (image != null) 'image': image,
    if (navigation.isNotEmpty) 'navigation': navigation,
    if (ignored.isNotEmpty) 'ignored': ignored,
    'instances': [for (final i in instances) i.toJson()],
    'guided': [for (final g in guided) g.toJson()],
    'devNotes': {for (final m in used) m.name: m.devNotes},
    'references': references,
    'components': [for (final c in components) c.toJson()],
  };
}

/// Tarefa de um componente, com brief próprio: **construir** um componente fora do DS (as instâncias do DS dentro
/// dele já saem resolvidas) ou **montar** um widget que já existe ([sketch]): do DS (`FigmaConnect.sketch`) ou do app
/// (`@FigmaLocal`).
class ComponentTask {
  ComponentTask({
    required this.name,
    required this.key,
    required this.definition,
    required this.variants,
    required this.uses,
    required this.guided,
    required this.devNotes,
    this.sketch,
    this.within = const {},
  });

  /// Sketch usado dentro de um componente local: id da instância → nome do componente.
  final Map<String, String> within;

  /// O mapeamento a montar (`FigmaConnect.sketch` ou `@FigmaLocal`); null num componente a construir.
  final Mapping? sketch;

  /// `build` (construir fora do DS), `sketch` (montar o widget do DS) ou `local` (montar o widget do app).
  String get kind => switch (sketch?.coverage) {
    null => 'build',
    'local' => 'local',
    _ => 'sketch',
  };

  final String name;
  final String key;

  /// Pasta em `components/`, arquivo em `widgets/` e classe: único na tela (nome repetido ganha o começo da key).
  late final String folder;

  /// `ComponentDef` do IR; null quando o export não trouxe a definição (só o PNG da tela ajuda).
  final Json? definition;

  /// Instâncias dentro de cada variant, pelo id da variant.
  final Map<String, List<ResolvedInstance>> variants;

  /// Instâncias na tela (placeholders); vazio quando só aparece dentro de outro componente local.
  final List<ResolvedInstance> uses;

  /// Decisões das instâncias do DS internas, com ids próprios do componente.
  final List<Guided> guided;
  final Map<String, List<String>> devNotes;

  /// Componentes locais usados dentro deste, pela key.
  Map<String, String> get dependencies => {
    for (final list in variants.values)
      for (final i in list)
        if (i.status == 'placeholder') i.componentKey: i.component,
  };

  Json toJson() => {
    'name': name,
    'key': key,
    'kind': kind,
    if (sketch?.widget case final widget?) ...{'widget': widget.name, 'import': '${widget.library.source.uri}'},
    'folder': folder,
    'definition': definition,
    'variants': {
      for (final MapEntry(:key, :value) in variants.entries) key: [for (final i in value) i.toJson()],
    },
    'uses': [for (final u in uses) u.toJson()],
    'guided': [for (final g in guided) g.toJson()],
    'devNotes': devNotes,
  };
}

/// Overrides que mudam estilo fora da API do componente: ficam no valor padrão do widget.
const _styleFields = {'fills', 'strokes', 'effects', 'opacity', 'cornerRadius', 'strokeWeight', 'fontSize'};

/// Overrides de conteúdo (texto, visibilidade, troca de componente) em camadas sem prop: o mapeamento não os lê.
const _contentFields = {'characters', 'visible', 'mainComponent', 'componentProperties'};

const _irVersions = {'1.0.0', '1.1.0', '1.2.0', '1.3.0', '1.4.0'};

String _overrideKind(List<Object?> fields) => fields.any(_contentFields.contains)
    ? 'content'
    : fields.any(_styleFields.contains)
    ? 'style'
    : 'layout';

/// Resolve as instâncias de uma tela do IR com os mapeamentos de [maps].
class Resolver {
  Resolver(this.maps);

  final MappingSet maps;
  final _guided = <Guided>[];
  final _used = <String, Mapping>{};
  final _ignored = <Json>[];
  String _instance = '';

  ResolvedScreen screen(Json ir, {String? screen, String? state}) {
    // Tokens já em Dart em tudo que vai para os briefs (árvores, overrides, componentes locais).
    if (maps.policy.tokens case final tokens?) {
      ir = {
        ...ir,
        for (final key in ['screens', 'components']) key: withDartTokens(ir[key], tokens),
      };
    }
    _guided.clear();
    _used.clear();
    _ignored.clear();
    if (!_irVersions.contains(ir['irVersion'])) {
      throw ResolveError('Versão de IR não suportada: ${ir['irVersion']} (aceitas: ${_irVersions.join(', ')}).');
    }
    if (ir['screens'] is! List || (ir['screens'] as List).isEmpty) {
      throw ResolveError('O export (kind=${ir['kind']}) não tem telas: exporte uma tela ou um fluxo.');
    }
    final screens = (ir['screens'] as List).cast<Json>();
    final def = screen == null
        ? (screens.length == 1 ? screens.single : throw ResolveError('Escolha a tela: ${_names(screens)}'))
        : screens.firstWhere(
            (s) => s['name'] == screen || (s['states'] as List).cast<Json>().any((st) => st['frameName'] == screen),
            orElse: () => throw ResolveError('Tela "$screen" não está no export: ${_names(screens)}'),
          );
    final states = (def['states'] as List).cast<Json>();
    final st = state == null
        ? states.firstWhere((s) => s['frameName'] == screen, orElse: () => states.first)
        : states.firstWhere(
            (s) => s['state'] == state,
            orElse: () => throw ResolveError('Estado "$state" não existe em ${def['name']}'),
          );

    final instances = _walk(st['tree'] as Json);
    return ResolvedScreen(
      screen: def['name'] as String,
      state: st['state'] as String,
      frameId: st['id'] as String,
      image: st['image'] as String?,
      imageScale: (st['imageScale'] as num?) ?? 2,
      tree: st['tree'] as Json,
      navigation: _navigation(ir, st['id'] as String, instances),
      ignored: List.of(_ignored),
      skeleton: maps.screen,
      instances: instances,
      guided: List.of(_guided),
      components: _localComponents(ir, instances),
      used: _used.values.toList(),
      references: _references(),
      tokens: maps.policy.tokens,
    );
  }

  /// Arestas do fluxo que saem do frame [frameId], com o gatilho ligado à instância da tela quando é uma.
  static List<Json> _navigation(Json ir, String frameId, List<ResolvedInstance> instances) {
    final names = {
      for (final s in (ir['screens'] as List).cast<Json>())
        for (final st in (s['states'] as List).cast<Json>())
          st['id']: (s['states'] as List).length > 1 ? '${s['name']} (${st['state']})' : s['name'],
    };
    final byId = {for (final i in instances) i.id: i};
    return [
      for (final e in ((ir['flow'] as Json?)?['edges'] as List? ?? const []).cast<Json>())
        if (e['from'] == frameId)
          {
            'trigger': (e['trigger'] as Json)['name'],
            'node': (e['trigger'] as Json)['node'],
            if (byId[(e['trigger'] as Json)['node']] case final i?) 'instance': i.path,
            'to': names[e['to']] ?? e['to'] ?? 'destino removido no Figma',
          },
    ];
  }

  Map<String, List<String>> get _devNotes => {for (final m in _used.values) m.name: m.devNotes};

  Map<String, String> _references() {
    final root = maps.root;
    if (root == null) return const {};
    final refs = References(root);
    return {
      for (final m in _used.values)
        if ((m.coverage != 'complete' || _guided.any((g) => g.component == m.name))
                ? refs.render(m, {
                    for (final g in _guided)
                      if (g.component == m.name) g.part,
                  })
                : ''
            case final md when md.isNotEmpty)
          m.name: md,
    };
  }

  List<ResolvedInstance> _walk(Json tree) {
    final instances = <ResolvedInstance>[];
    void walk(Json node, String path) {
      if (node['visible'] == false) return; // escondido no Figma: não entra na tela
      if (node['instance'] case final Json inst) {
        final annotated = maps.components.any((m) => m.key == inst['componentKey'] || m.key == inst['mainComponentKey']);
        if (maps.policy.ignoreReason(inst, annotated: annotated) case final reason?) {
          _ignored.add({'path': path, 'component': inst['componentName'], 'reason': reason});
        } else {
          instances.add(_node(node, path));
        }
        return;
      }
      for (final child in (node['children'] as List? ?? const []).cast<Json>()) {
        walk(child, path.isEmpty ? child['name'] as String : '$path/${child['name']}');
      }
    }

    walk(tree, '');
    return instances;
  }

  /// Os placeholders da tela e, dentro deles, os de outros componentes locais; dependências primeiro.
  List<ComponentTask> _localComponents(Json ir, List<ResolvedInstance> instances) {
    final defs = {for (final c in (ir['components'] as List? ?? const []).cast<Json>()) c['key'] as String: c};
    final uses = <String, List<ResolvedInstance>>{};
    for (final i in instances.where((i) => i.status == 'placeholder')) {
      (uses[i.componentKey] ??= []).add(i);
    }
    final done = <String, ComponentTask>{};
    final visiting = <String>{};
    void visit(String key, String name) {
      if (!visiting.add(key)) return; // já feito, ou ciclo
      // Resolver novo: as decisões do componente têm ids próprios e não entram nas da tela.
      final c = Resolver(maps)._component(key, name, defs[key], uses[key] ?? const []);
      for (final MapEntry(:key, value: name) in c.dependencies.entries) {
        visit(key, name);
      }
      done[key] = c;
    }

    for (final MapEntry(:key, value: list) in uses.entries) {
      visit(key, list.first.component);
    }
    // Sketches e widgets do app (`@FigmaLocal`), da tela e de dentro dos componentes locais: brief de montagem.
    final sketches = <Mapping, List<ResolvedInstance>>{};
    final within = <String, String>{};
    void addSketches(Iterable<ResolvedInstance> list, [String? owner]) {
      for (final i in list.where((i) => i.status == 'sketch' || i.status == 'local')) {
        (sketches[i.mapping!] ??= []).add(i);
        if (owner != null) within[i.id] = owner;
      }
    }

    addSketches(instances);
    for (final c in done.values.toList()) {
      for (final list in c.variants.values) {
        addSketches(list, c.name);
      }
    }
    for (final MapEntry(key: m, value: list) in sketches.entries) {
      done['sketch:${m.file}#${m.functionName}'] = ComponentTask(
        name: m.name,
        key: m.key,
        definition: null,
        variants: const {},
        uses: list,
        guided: const [],
        devNotes: {m.name: m.devNotes},
        sketch: m,
        within: {for (final i in list) if (within[i.id] case final owner?) i.id: owner},
      );
    }
    final taken = <String>{};
    for (final c in done.values) {
      final base = snakeCase(c.name);
      c.folder = taken.add(base) ? base : '${base}_${c.key.length > 6 ? c.key.substring(0, 6) : c.key}';
      taken.add(c.folder);
    }
    return done.values.toList();
  }

  ComponentTask _component(String key, String name, Json? def, List<ResolvedInstance> uses) {
    final variants = {
      for (final v in (def?['variants'] as List? ?? const []).cast<Json>()) v['id'] as String: _walk(v['tree'] as Json),
    };
    return ComponentTask(
      name: name,
      key: key,
      definition: def,
      variants: variants,
      uses: uses,
      guided: List.of(_guided),
      devNotes: _devNotes,
    );
  }

  ResolvedInstance _node(Json node, String path) {
    final inst = node['instance'] as Json;
    final size = node['size'] as Json;
    final component = inst['componentName'] as String;
    _instance = node['id'] as String;
    final before = _guided.length;
    Mapping? mapping;
    String? code;
    String? error;
    // Um valor sem correspondência derruba só esta instância, não a tela.
    try {
      // Componente principal apagado ou inacessível no Figma: não dá para mapear nem construir.
      if ((inst['componentKey'] as String).isEmpty) throw ResolveError('instância sem componente principal no Figma');
      mapping = maps.find(
        componentKey: inst['componentKey'] as String,
        mainComponentKey: inst['mainComponentKey'] as String?,
        props: inst['props'] as Json,
      );
      if (mapping?.coverage == 'sketch' || mapping?.coverage == 'local') {
        // Sem corpo para avaliar: a instância vira tarefa de montagem com brief próprio.
        _used.putIfAbsent(mapping!.name, () => mapping!);
      } else if (mapping != null) {
        code = _evaluate(mapping, _Scope(inst['props'] as Json, (inst['exposed'] as List).cast<Json>(), component));
      }
    } on ResolveError catch (e) {
      _guided.removeRange(before, _guided.length);
      error = e.message;
    }
    // Sem mapeamento: do DS (no retrato da biblioteca; sem retrato, remoto) é gap; o resto é a construir.
    final assemble = error == null && (mapping?.coverage == 'sketch' || mapping?.coverage == 'local');
    final status = assemble
        ? mapping!.coverage
        : code != null
        ? 'mapped'
        : (error != null || maps.fromDs(inst) ? 'gap' : 'placeholder');
    if (code == null) {
      final marker = assemble
          ? 'f2d:$status $component → ${mapping!.widget!.name}'
          : status == 'gap'
          ? 'f2d:gap $component: ${error ?? 'sem mapeamento'}'
          : 'f2d:placeholder component $component (${node['id']}, key ${(inst['componentKey'] as String).padRight(8).substring(0, 8).trim()})';
      code = '/* $marker */ const SizedBox(width: ${size['width']}, height: ${size['height']}, child: Placeholder())';
    }
    return ResolvedInstance(
      id: node['id'] as String,
      name: node['name'] as String,
      path: path,
      component: component,
      componentKey: inst['componentKey'] as String,
      status: status,
      code: code,
      mapping: mapping,
      error: error,
      guided: [for (final g in _guided.skip(before)) g.id],
      figma: assemble || status == 'placeholder'
          ? {
              'props': _readable(inst['props'] as Json),
              'exposed': [
                for (final e in (inst['exposed'] as List).cast<Json>()) {...e, 'props': _readable(e['props'] as Json)},
              ],
              if (inst['content'] case final List<Object?> content)
                'content': [
                  for (final c in content.cast<Json>())
                    {...c, if (c['props'] case final Json props) 'props': _readable(props)},
                ],
              if (inst['contentTruncated'] == true) 'contentTruncated': true,
            }
          : null,
      bounds: node['bounds'] as Json?,
      overrides: [
        for (final o in (inst['overrides'] as List).cast<Json>())
          {
            'node': o['node'],
            'fields': o['fields'],
            'kind': _overrideKind(o['fields'] as List<Object?>),
            if (o['values'] != null) 'values': o['values'],
          },
      ],
    );
  }

  String _evaluate(Mapping mapping, _Scope scope) {
    _used.putIfAbsent(mapping.name, () => mapping);
    final fn = mapping.function!.functionExpression;
    final body = fn.body;
    if (body is! ExpressionFunctionBody) {
      throw ResolveError('${mapping.functionName} (${mapping.file}) precisa ser uma função de expressão (=>).');
    }
    final param = fn.parameters!.parameters.first.name!.lexeme;
    return _Eval(this, mapping, {param: scope}).emit(body.expression);
  }

  /// Instância exposta lida com `f.instance(path)`: resolvida pelo mapeamento dela.
  String _exposed(_Scope scope, String path) {
    final entry = scope.entry(path);
    final props = entry['props'] as Json;
    final mapping = maps.find(
      componentKey: entry['componentKey'] as String,
      mainComponentKey: entry['mainComponentKey'] as String?,
      props: props,
    );
    if (mapping == null) return '/* f2d:gap ${entry['componentName']} sem mapeamento */ const Placeholder()';
    return _evaluate(mapping, _Scope(props, scope.below(path), entry['componentName'] as String));
  }

  String _guide(Mapping mapping, String part, String guide, Json figma) {
    final id = 'G${_guided.length + 1}';
    _guided.add(Guided(id, _instance, mapping.name, part, guide, figma));
    return id;
  }

  /// Props para a LLM ler: ícone (troca para uma instância de um mapeamento `kind: icon`) já como código Dart
  /// validado contra o enum de ícones da política, em vez do objeto cru do Figma.
  Json _readable(Json props) {
    final icons = maps.policy.icons;
    if (icons == null) return props;
    final iconKeys = {
      for (final m in maps.components)
        if (m.kind == 'icon') m.key,
    };
    return {
      for (final MapEntry(:key, :value) in props.entries)
        key: value is Json && (iconKeys.contains(value['componentKey']) || iconKeys.contains(value['mainComponentKey']))
            ? iconCode(value, icons, byKey: maps.policy.iconByKey)
            : value,
    };
  }

  static String _names(List<Json> screens) => screens.map((s) => '"${s['name']}"').join(', ');
}

/// Props e instâncias expostas visíveis para uma chamada `f.*`.
class _Scope {
  _Scope(this.props, this.exposed, this.component);

  final Json props;

  /// Instâncias expostas abaixo desta, com o caminho relativo a ela.
  final List<Json> exposed;
  final String component;

  /// A prop do componente ou, como no painel do Figma, de uma instância exposta dele: o `Button Icon` lê o
  /// `✏️ Type` da base travada que expõe (`.Icon Button / Large`), sem anotação para a base. Prop em duas expostas
  /// é erro: a anotação diz qual com `f.nested`.
  Object prop(String name) {
    if (props[name] case final value?) return value;
    final found = [
      for (final e in exposed)
        if ((e['props'] as Json)[name] case final value?) (e['path'], value),
    ];
    return switch (found) {
      [(_, final value)] => value,
      [] => throw ResolveError('$component não tem a prop "$name" no export (props: ${props.keys.join(', ')})'),
      _ => throw ResolveError(
        '$component: a prop "$name" está em ${found.map((f) => f.$1).join(' e ')}; leia com f.nested(<caminho>)',
      ),
    };
  }

  Json entry(String path) => exposed.firstWhere(
    (e) => e['path'] == path,
    orElse: () =>
        throw ResolveError('$component não expõe "$path" (expostas: ${exposed.map((e) => e['path']).join(', ')})'),
  );

  List<Json> below(String path) => [
    for (final e in exposed)
      if ((e['path'] as String).startsWith('$path/')) {...e, 'path': (e['path'] as String).substring(path.length + 1)},
  ];

  _Scope nested(String path) {
    final e = entry(path);
    return _Scope(e['props'] as Json, below(path), e['componentName'] as String);
  }
}

/// Reescreve o corpo de um mapeamento trocando cada `f.*` pelo valor do Figma. O resto do código fica como está.
class _Eval {
  _Eval(this.r, this.mapping, this.bindings);

  final Resolver r;
  final Mapping mapping;
  final Map<String, _Scope> bindings;

  String get _source => mapping.source;

  String emit(AstNode node) {
    if (node is MethodInvocation) {
      if (_scopeOf(node.target) case final scope?) return _call(node, scope);
      if (_inline(node) case final code?) return code;
    }
    if (node is ConditionalExpression) {
      final condition = emit(node.condition); // uma vez só: um f.guided aqui não pode virar duas decisões
      return switch (condition.trim()) {
        'true' => emit(node.thenExpression),
        'false' => emit(node.elseExpression),
        _ => '$condition ? ${emit(node.thenExpression)} : ${emit(node.elseExpression)}',
      };
    }
    final out = StringBuffer();
    var pos = node.offset;
    for (final child in node.childEntities.whereType<AstNode>()) {
      out
        ..write(_source.substring(pos, child.offset))
        ..write(emit(child));
      pos = child.end;
    }
    return (out..write(_source.substring(pos, node.end))).toString();
  }

  _Scope? _scopeOf(Expression? target) => switch (target) {
    SimpleIdentifier(:final name) => bindings[name],
    MethodInvocation(methodName: SimpleIdentifier(name: 'nested'), target: final inner) => _scopeOf(
      inner,
    )?.nested(_string(_argument(target.argumentList.arguments.first))),
    _ => null,
  };

  String _call(MethodInvocation m, _Scope s) {
    final args = [for (final a in m.argumentList.arguments) _argument(a)];
    final named = {
      for (final a in m.argumentList.arguments.whereType<NamedExpression>()) a.name.label.name: a.expression,
    };
    String name() => _string(args.first);
    switch (m.methodName.name) {
      case 'text':
        return _literal(s.prop(name()) as String);
      case 'boolean':
        return '${s.prop(name()) as bool}';
      case 'variant':
        final prop = name();
        final value = s.prop(prop);
        final entries = (args[1] as SetOrMapLiteral).elements.whereType<MapLiteralEntry>();
        for (final entry in entries) {
          if (entry.key is StringLiteral && _string(entry.key) == value) return emit(entry.value);
        }
        throw ResolveError('${mapping.name}: variant $prop=$value sem mapeamento em ${mapping.functionName}');
      case 'icon':
        return _icon(m, s.prop(name()));
      case 'instance':
        return r._exposed(s, name());
      case 'slot':
        return '/* f2d:gap slot ${name()} */ const SizedBox.shrink()';
      case 'guided':
        final part = name();
        final id = r._guide(mapping, part, _string(named['guide']!), s.props);
        return '/* f2d:guided $id $part */ ${emit(named['or']!)}';
      default:
        throw ResolveError('${mapping.functionName}: f.${m.methodName.name} não é suportado pelo resolvedor');
    }
  }

  /// Ícone pela convenção de nomes (`arrow-up-right` → `arrowUpRight`), conferido contra o enum do tipo esperado ou,
  /// quando o tipo não é enum (`AcmeIconData`), contra a classe de `IconTable.constants` da política.
  String _icon(MethodInvocation m, Object value) {
    final policy = r.maps.policy;
    final type = switch (m.staticType?.element) {
      final EnumElement e => e,
      _ when policy.icons is! EnumElement => policy.icons,
      _ => null,
    };
    if (type == null) {
      throw ResolveError(
        '${mapping.functionName}: f.icon precisa de um enum como destino, ou de IconTable.constants na política',
      );
    }
    return iconCode(value, type, byKey: type == policy.icons ? policy.iconByKey : const {});
  }

  /// Função auxiliar do próprio arquivo chamada com `f` (ex.: `_size(f)`): avaliada no lugar, com `f` ligado.
  String? _inline(MethodInvocation m) {
    if (m.target != null) return null;
    final fn = mapping.unit.declarations
        .whereType<FunctionDeclaration>()
        .where((d) => d.name.lexeme == m.methodName.name)
        .firstOrNull
        ?.functionExpression;
    final body = fn?.body;
    if (fn == null || body is! ExpressionFunctionBody) return null;
    final inner = <String, _Scope>{};
    final params = fn.parameters!.parameters;
    final args = [for (final a in m.argumentList.arguments) _argument(a)];
    for (var i = 0; i < params.length && i < args.length; i++) {
      if (_scopeOf(args[i]) case final scope?) inner[params[i].name!.lexeme] = scope;
    }
    if (inner.isEmpty) return null;
    return _Eval(r, mapping, inner).emit(body.expression);
  }

  Expression _argument(Expression argument) => argument is NamedExpression ? argument.expression : argument;

  String _string(Expression? e) => switch (e) {
    StringLiteral(:final stringValue?) => stringValue,
    _ => throw ResolveError('${mapping.functionName}: esperava um texto literal em "$e"'),
  };

  static String _literal(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
}
