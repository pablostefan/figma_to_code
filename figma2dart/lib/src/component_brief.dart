import 'dart:convert';

import 'api.dart';
import 'names.dart';
import 'resolve.dart';
import 'structure.dart';
import 'tokens.dart';

/// O `BRIEF.md` da tarefa de um componente, num padrão fixo: construir um componente fora do DS, ou montar um
/// componente do DS anotado com `FigmaConnect.sketch`. [folders] dá a pasta da tarefa de uma instância (para
/// os links); [images], as imagens que existem na pasta da tarefa (null: todas as citadas no IR); [references], os
/// docs e exemplos já recortados; [screenImage], o PNG da tela.
String componentBrief(
  ComponentTask c, {
  String? Function(ResolvedInstance)? folders,
  Set<String>? images,
  String? references,
  String? screenImage,
  Tokens? tokens,
  Map<String, String> crops = const {},
}) {
  if (c.sketch != null) return _sketchBrief(c, references: references, screenImage: screenImage, crops: crops);
  final def = c.definition;
  final cls = pascalCase(c.folder);
  final out = StringBuffer()
    ..writeln('# Construir: ${c.name}')
    ..writeln()
    ..writeln('Componente fora do DS (key `${c.key}`${def == null ? '' : ', figma ${def['id']}'}).')
    ..writeln('Construa só se o usuário escolher; até lá a tela usa o placeholder `f2d:placeholder`.');
  if (def?['description'] case final String description when description.isNotEmpty) {
    out
      ..writeln()
      ..writeln('> $description');
  }

  out
    ..writeln()
    ..writeln('## Onde criar')
    ..writeln()
    ..writeln('`widgets/${c.folder}.dart`, na pasta do arquivo da tela; classe `$cls` (`StatelessWidget`).');

  if (def == null) {
    out
      ..writeln()
      ..writeln('**O export não trouxe a definição deste componente.** Use o PNG da tela e os usos abaixo.');
  } else {
    final props = (def['props'] as Json).cast<String, Json>();
    final exposed = _varyingExposed(c.uses);
    out
      ..writeln()
      ..writeln('## API proposta (das props do Figma)')
      ..writeln()
      ..writeln('```dart')
      ..write(_api(cls, props, exposed))
      ..writeln('```')
      ..writeln()
      ..writeln('Callbacks e textos de acessibilidade não existem no Figma: decida pelo uso na tela e marque com')
      ..writeln('`f2d:inferred`.');
    if (exposed.isNotEmpty) {
      out
        ..writeln()
        ..writeln('Instância exposta cuja prop muda entre os usos vira parâmetro (acima); o widget repassa o valor ao')
        ..writeln('widget do DS de dentro. Não fixe o valor de exemplo do Figma.');
    }

    final variants = (def['variants'] as List).cast<Json>();
    String? png(Json v) => switch (v['image']) {
      final String path when images == null || images.contains(path) => '`../../$path`',
      _ => null,
    };
    if (variants.length > 1 || variants.any((v) => png(v) != null)) {
      out
        ..writeln()
        ..writeln('## Variantes')
        ..writeln()
        ..writeln('| Variant | Props | PNG |')
        ..writeln('|---|---|---|');
      for (final v in variants) {
        final values = (v['props'] as Json).entries.map((e) => '${e.key}=${e.value}').join(', ');
        out.writeln('| `${v['name']}` | ${values.isEmpty ? '—' : values} | ${png(v) ?? '—'} |');
      }
    }

    // Uma árvore só (a primeira variant) e, para as outras, só o que muda: N árvores quase iguais escondem a regra.
    final paths = {
      for (final u in c.uses)
        for (final e in (u.figma?['exposed'] as List? ?? const []).cast<Json>()) e['path'] as String,
    };
    List<StructureLine> lines(Json v) => structureLines(
      v['tree'] as Json,
      {for (final i in c.variants[v['id']] ?? const <ResolvedInstance>[]) i.id: i},
      (i) => '../${folders?.call(i) ?? snakeCase(i.component)}/BRIEF.md',
      exposed: paths,
    );
    final base = variants.isEmpty ? const <StructureLine>[] : lines(variants.first);
    out
      ..writeln()
      ..writeln('## Estrutura${variants.length > 1 ? ' (base: `${variants.first['name']}`)' : ''}')
      ..writeln()
      ..writeln(structureLegend(tokens))
      ..writeln();
    for (final l in base) {
      out.writeln('${'  ' * l.depth}- `${l.name}`: ${l.parts.join(' · ')}');
    }
    if (variants.length > 1) {
      out
        ..writeln()
        ..writeln('## O que muda em cada variante')
        ..writeln()
        ..writeln('Em relação à base; camada e atributo que não aparecem aqui são iguais. `antes → agora`.')
        ..writeln();
      for (final v in variants.skip(1)) {
        final diff = _diff(base, lines(v));
        out.writeln('- `${v['name']}`${diff.isEmpty ? ': igual à base' : ':'}');
        for (final d in diff) {
          out.writeln('  - $d');
        }
      }
    }
    for (final v in variants.where((v) => v['svg'] != null)) {
      out
        ..writeln()
        ..writeln(
          'SVG de `${v['name']}` (do Figma): `${svgFile(v)}`, nesta pasta. Use como asset do pacote, com o que o',
        )
        ..writeln('app já usa para SVG; sem isso, fica o `TODO(f2d)` da estrutura.');
    }
  }

  if (c.uses.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Usos na tela')
      ..writeln()
      ..writeln('O que a tela passa em cada instância:')
      ..writeln();
    for (final u in c.uses) {
      final exposed = (u.figma?['exposed'] as List? ?? const []).cast<Json>();
      out.writeln(
        '- `${u.path}` (${u.id}): `${jsonEncode(u.figma?['props'])}`'
        '${exposed.isEmpty ? '' : ' · expostas `${jsonEncode({for (final e in exposed) e['path']: e['props']})}`'}',
      );
    }
  } else {
    out
      ..writeln()
      ..writeln('Usado só dentro de outros componentes locais.');
  }

  if (c.guided.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Decisões (f2d:guided)')
      ..writeln();
    for (final g in c.guided) {
      out.writeln('- **${g.id}** ${g.component} · `${g.part}` — ${g.guide}');
    }
  }

  out
    ..writeln()
    ..writeln('## Regras')
    ..writeln()
    ..writeln('- Componha com os widgets do DS (o código das instâncias do DS acima já está resolvido) e só tokens.')
    ..writeln('- O tamanho no fim da linha de uma instância do DS é o do Figma: se o widget tem parâmetro de tamanho')
    ..writeln('  com outro padrão (ex.: `DsIcon` 24, Figma 20), passe o do Figma.')
    ..writeln('- Texto ligado a uma prop (`← prop`) vira parâmetro; texto sem ligação é fixo no componente.')
    ..writeln('- Componente local dentro deste: construa o dele antes (link na estrutura).')
    ..writeln('- Um teste de widget por variant; o que você decidiu sem o Figma, marque com `f2d:inferred`.');
  for (final MapEntry(key: component, value: notes) in c.devNotes.entries) {
    for (final note in notes) {
      out.writeln('- $component: $note');
    }
  }
  return out.toString();
}

/// Montar um widget que já existe e que a anotação não mapeia campo a campo: do DS (`FigmaConnect.sketch`) ou do
/// app (`@FigmaLocal`). A API dele, os dados de cada instância na tela e o norte. Não há código pronto: a LLM
/// escreve o widget no lugar do placeholder `f2d:sketch`/`f2d:local`.
String _sketchBrief(ComponentTask c, {String? references, String? screenImage, Map<String, String> crops = const {}}) {
  final m = c.sketch!;
  final widget = m.widget!;
  final local = c.kind == 'local';
  final out = StringBuffer()
    ..writeln('# Montar: ${c.name} → `${widget.name}`')
    ..writeln()
    ..writeln(
      local
          ? 'Widget do app (fora do DS) que já existe, ligado ao Figma por `@FigmaLocal` (key `${c.key}`, em'
                '\n`${m.file}`).'
          : 'Componente do DS anotado com `FigmaConnect.sketch` (key `${c.key}`): a anotação não mapeia o Figma '
                'campo\na campo.',
    )
    ..writeln(
      'Na tela, cada instância está como placeholder `f2d:${c.kind}`; troque-o pelo `${widget.name}` montado com a',
    )
    ..writeln('API, os dados do Figma e o norte abaixo. O `check` só passa quando não sobrar o marcador.')
    ..writeln()
    ..writeln("Import: `import '${widget.library.uri}';`");
  if (screenImage != null) {
    out
      ..writeln()
      ..writeln('Referência visual: `../../$screenImage`.');
  }
  if (m.guide case final guide?) {
    out
      ..writeln()
      ..writeln('## Norte')
      ..writeln()
      ..writeln(guide);
  }
  out
    ..writeln()
    ..writeln('## API do widget (do código)')
    ..writeln()
    ..writeln('```dart')
    ..writeln(widgetApi(widget))
    ..writeln('```')
    ..writeln()
    ..writeln('## Instâncias na tela');
  for (final u in c.uses) {
    out
      ..writeln()
      ..writeln(
        '### `${u.path}` (${u.id})${switch (c.within[u.id]) {
          final owner? => ' — dentro do componente local **$owner** (monte no widget dele)',
          _ => '',
        }}',
      )
      ..writeln()
      ..writeln('- Props do Figma: `${jsonEncode(u.figma?['props'])}`');
    if (crops[u.id] case final file?) out.writeln('- Recorte do Figma: `$file` (nesta pasta)');
    if (u.figma?['content'] case final List<Object?> content when content.isNotEmpty) {
      out.writeln(
        '- Conteúdo dentro da instância, como está no Figma'
        '${u.figma?['contentTruncated'] == true ? ' (cortado nos primeiros ${content.length} itens)' : ''}:',
      );
      for (final item in content.cast<Json>()) {
        out.writeln(
          '  - `${item['path']}`: ${switch (item) {
            {'text': final text} => jsonEncode(text),
            _ => '${item['component']} `${jsonEncode(item['props'])}`',
          }}',
        );
      }
    }
    // O `content` (IR 1.3) já lista as instâncias de dentro; as expostas só para export sem ele.
    if (u.figma?['exposed'] case final List<Object?> exposed when exposed.isNotEmpty && u.figma?['content'] == null) {
      out.writeln('- Instâncias expostas:');
      for (final e in exposed.cast<Json>()) {
        out.writeln('  - `${e['path']}`: ${e['componentName']} `${jsonEncode(e['props'])}`');
      }
    }
    for (final o in u.overrides.where((o) => o['values'] != null)) {
      out.writeln('- Sobrescrito em `${o['node']}`: `${jsonEncode(o['values'])}`');
    }
  }
  if (references != null) {
    out
      ..writeln()
      ..writeln('## Docs e exemplos')
      ..writeln()
      ..writeln(references);
  }
  out
    ..writeln()
    ..writeln('## Regras')
    ..writeln()
    ..writeln(
      local
          ? '- Use só a API acima; não altere o `${widget.name}` sem perguntar ao usuário (outras telas o usam).'
          : '- Use só a API acima e widgets do DS; não altere o `${widget.name}` nem crie variação dele.',
    )
    ..writeln('- Valores que o Figma tem (textos, variantes, visibilidade) entram como estão. Conteúdo de exemplo do')
    ..writeln('  designer (linhas, itens) vem dos dados da tela, conforme o norte e os docs.')
    ..writeln('- O que decidir sem base neste brief: `// f2d:inferred — <motivo>`.');
  for (final note in m.devNotes) {
    out.writeln('- $note');
  }
  return out.toString();
}

/// Nomes dos parâmetros da API proposta (props do Figma e expostas que mudam nos usos), para o `check` conferir.
List<String> apiParams(ComponentTask c) => [
  for (final figma in ((c.definition?['props'] as Json?) ?? const {}).keys) _propParam(figma),
  for (final MapEntry(key: path, value: props) in _varyingExposed(c.uses).entries)
    for (final prop in props.keys) _exposedParam(path, prop),
];

/// Nome do parâmetro de uma prop do Figma e de uma prop de instância exposta: o mesmo no brief e no `check`.
String _propParam(String figma) => identifier(figma);
String _exposedParam(String path, String prop) => identifier('$path $prop');

/// Arquivo do SVG de uma variant na pasta da tarefa.
String svgFile(Json variant) => '${snakeCase(variant['name'] as String)}.svg';

/// Props de instâncias expostas que mudam entre os usos (caminho → prop → valor de cada uso): o componente precisa
/// recebê-las por parâmetro.
Map<String, Map<String, List<Object?>>> _varyingExposed(List<ResolvedInstance> uses) {
  final values = <String, Map<String, List<Object?>>>{};
  for (final u in uses) {
    for (final e in (u.figma?['exposed'] as List? ?? const []).cast<Json>()) {
      for (final MapEntry(:key, :value) in (e['props'] as Json).entries) {
        ((values[e['path'] as String] ??= {})[key] ??= []).add(value);
      }
    }
  }
  return {
    for (final MapEntry(key: path, value: props) in values.entries)
      if ({
            for (final MapEntry(:key, :value) in props.entries)
              if (value.map(jsonEncode).toSet().length > 1) key: value,
          }
          case final varying when varying.isNotEmpty)
        path: varying,
  };
}

/// O que muda de [base] para [variant], camada por camada (pelo caminho): partes que saíram → partes que entraram.
List<String> _diff(List<StructureLine> base, List<StructureLine> variant) {
  // Irmãos com o mesmo nome: o segundo vira `caminho#2`.
  Map<String, List<String>> byPath(List<StructureLine> lines) {
    final seen = <String, int>{};
    final out = <String, List<String>>{};
    for (final l in lines) {
      final n = seen[l.path] = (seen[l.path] ?? 0) + 1;
      out[n == 1 ? l.path : '${l.path}#$n'] = l.parts;
    }
    return out;
  }

  final before = byPath(base);
  final after = byPath(variant);
  final diff = <String>[];
  for (final MapEntry(key: path, value: now) in after.entries) {
    final old = before[path];
    if (old == null) {
      diff.add('`$path`: camada nova — ${now.join(' · ')}');
      continue;
    }
    final gone = old.where((p) => !now.contains(p)).join(' · ');
    final added = now.where((p) => !old.contains(p)).join(' · ');
    if (gone.isNotEmpty || added.isNotEmpty) {
      diff.add('`$path`: ${gone.isEmpty ? '(nada)' : gone} → ${added.isEmpty ? '(nada)' : added}');
    }
  }
  for (final path in before.keys.where((p) => !after.containsKey(p))) {
    diff.add('`$path`: não existe nesta variante');
  }
  return diff;
}

String _api(String cls, Map<String, Json> props, [Map<String, Map<String, List<Object?>>> exposed = const {}]) {
  final enums = StringBuffer();
  final params = <String>[];
  final fields = <String>[];
  for (final MapEntry(key: figma, value: p) in props.entries) {
    final name = _propParam(figma);
    final options = (p['options'] as List? ?? const []).cast<String>();
    final (type, init) = switch (p['type']) {
      'TEXT' => ('String', null),
      'BOOLEAN' => ('bool', '${p['default']}'),
      'VARIANT' when options.toSet().containsAll({'true', 'false'}) && options.length == 2 => (
        'bool',
        '${p['default']}',
      ),
      'VARIANT' => ('$cls${pascalCase(figma)}', '$cls${pascalCase(figma)}.${identifier(p['default'] as String)}'),
      _ => ('Widget', null), // INSTANCE_SWAP, SLOT
    };
    if (p['type'] == 'VARIANT' && type != 'bool') {
      enums
        ..writeln()
        ..writeln('/// Figma `$figma`.')
        ..writeln('enum $type { ${options.map(identifier).join(', ')} }');
    }
    params.add(init == null ? 'required this.$name' : 'this.$name = $init');
    fields
      ..add('')
      ..add('  /// Figma `$figma` (${p['type']}, padrão `${p['default']}`).')
      ..add('  final $type $name;');
  }
  for (final MapEntry(key: path, value: varying) in exposed.entries) {
    for (final MapEntry(key: prop, value: values) in varying.entries) {
      final name = _exposedParam(path, prop);
      // Ícone já sai como código (`DsIconName.x`): o tipo é o enum.
      final type = switch (values) {
        _ when values.every((v) => v is bool) => 'bool',
        _ when values.every((v) => v is String && RegExp(r'^[A-Z]\w*\.\w+$').hasMatch(v)) =>
          (values.first! as String).split('.').first,
        _ => 'String',
      };
      params.add('required this.$name');
      fields
        ..add('')
        ..add('  /// Figma: instância exposta `$path`, prop `$prop` (muda nos usos: ${values.toSet().join(', ')}).')
        ..add('  final $type $name;');
    }
  }
  return [
    'class $cls extends StatelessWidget {',
    '  const $cls({${[...params, 'super.key'].join(', ')}});',
    ...fields,
    '',
    '  @override',
    '  Widget build(BuildContext context) => …;',
    '}',
    if (enums.isNotEmpty) enums.toString().trimRight(),
    '',
  ].join('\n');
}
