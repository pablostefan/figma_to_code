import 'dart:convert';

import 'api.dart';
import 'resolve.dart';
import 'structure.dart';

/// O `BRIEF.md` da tela: ponto de entrada da LLM. Mostra o código de cada instância já resolvido e o que ela decide.
/// [images]: as imagens que existem na pasta da tarefa (null: todas as citadas no IR).
String brief(ResolvedScreen s, {Set<String>? images}) {
  String brief(ResolvedInstance i) => 'components/${taskOf(s, i)?.folder}/BRIEF.md';
  final image = images == null || images.contains(s.image) ? s.image : null;
  final out = StringBuffer()
    ..writeln('# Tarefa: tela ${s.screen} (figma ${s.frameId})')
    ..writeln()
    ..writeln(
      'Estado: `${s.state}`. Referência visual: ${image == null ? 'o PNG da tela no export do plugin' : '`$image`'}.',
    )
    ..writeln()
    ..writeln('O código abaixo saiu dos mapeamentos `@FigmaConnect` com os valores do Figma: **não altere o que não')
    ..writeln(
      'está marcado**. Resolva os pontos `f2d:guided` e `f2d:gap`. `f2d:placeholder` só sai quando o componente',
    )
    ..writeln('fora do DS foi construído (escolha do usuário); senão fica.')
    ..writeln(
      '`f2d:sketch` (componente do DS) e `f2d:local` (widget do app que já existe) são para **montar**: troque o',
    )
    ..writeln(
      'placeholder pelo widget seguindo o brief dele (API do widget, dados do Figma e norte), em "Componentes a',
    )
    ..writeln('montar".')
    ..writeln();

  out.writeln('## Componentes');
  for (final i in s.instances) {
    out
      ..writeln()
      ..writeln('### ${i.path} — ${i.component} (${_status[i.status]}, ${i.id})')
      ..writeln();
    out
      ..writeln('```dart')
      ..writeln(i.code)
      ..writeln('```');
    if (i.status == 'sketch' || i.status == 'local') out.writeln('Montar: [brief](${brief(i)})');
    for (final o in i.overrides) {
      final at = '`${o['node']}` (${(o['fields'] as List).join(', ')})';
      switch (o['kind']) {
        case 'style':
          out.writeln('- Override de estilo fora da API em $at: fica o valor padrão.');
        case 'content':
          out.writeln(
            '- **f2d:gap** override de conteúdo em $at: ${jsonEncode(o['values'])}. O mapeamento não lê essa camada;'
            ' aplique o valor no código.',
          );
      }
    }
  }

  if (s.skeleton case final skeleton?) {
    out
      ..writeln()
      ..writeln('## Esqueleto da tela (@FigmaScreen)')
      ..writeln()
      ..writeln(
        'Toda tela do DS usa este esqueleto: `s.body()` é o conteúdo da "Estrutura da tela" abaixo; `s.instance(x)`',
      )
      ..writeln('é a instância do componente `x` quando a tela tem uma, ou nada.')
      ..writeln()
      ..writeln('```dart')
      ..writeln(skeleton)
      ..writeln('```');
  }

  if (s.tree.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Estrutura da tela')
      ..writeln()
      ..writeln('Layout do frame, de fora para dentro. ${structureLegend(s.tokens, text: s.text != null)}')
      ..writeln();
    writeStructure(out, s.tree, {for (final i in s.instances) i.id: i}, brief, inline: false);
  }

  if (s.navigation.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Navegação (protótipo do Figma)')
      ..writeln();
    for (final n in s.navigation) {
      final at = n['instance'] == null ? '`${n['trigger']}` (${n['node']})' : '`${n['instance']}` (${n['node']})';
      out.writeln('- $at → ${n['to'] == 'back' ? 'voltar' : '**${n['to']}**'}');
    }
  }

  if (s.guided.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Decisões (f2d:guided)')
      ..writeln();
    for (final g in s.guided) {
      out.writeln('- **${g.id}** ${g.component} · `${g.part}` — ${g.guide}');
    }
  }

  // Componente `complete` sem regra e sem decisão nesta tela não aparece: já está resolvido no código.
  // O sketch tem brief próprio (norte, API, docs): aqui só repetiria. Complete sem regra, nota nem decisão já está
  // resolvido no código.
  final described = s.used.where(
    (m) =>
        m.coverage != 'sketch' &&
        m.coverage != 'local' &&
        (m.coverage == 'partial' || m.devNotes.isNotEmpty || m.figmaNotes.isNotEmpty || s.references[m.name] != null),
  );
  if (described.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Componentes desta tela: norte, regras, docs e exemplos');
    for (final m in described) {
      out
        ..writeln()
        ..writeln('### ${m.name}${m.coverage == 'complete' ? '' : ' (${m.coverage})'}')
        ..writeln();
      final head = [
        if (m.guide case final guide? when m.coverage != 'complete') 'Norte: $guide',
        for (final note in m.devNotes) '- $note',
        for (final note in m.figmaNotes) '- $note',
      ];
      if (head.isNotEmpty) out.writeln(head.join('\n'));
      // Parcial: as decisões preenchem parâmetros do widget; a API mostra quais existem e de que tipo.
      if (m.widget case final widget? when m.coverage == 'partial') {
        out
          ..writeln()
          ..writeln('API do widget:')
          ..writeln()
          ..writeln('```dart')
          ..writeln(widgetApi(widget))
          ..writeln('```');
      }
      if (s.references[m.name] case final refs?) {
        if (head.isNotEmpty) out.writeln();
        out.writeln(refs);
      }
    }
  }

  final pending = s.instances.where((i) => const {'gap', 'placeholder'}.contains(i.status)).toList();
  if (pending.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Fora do mapeamento')
      ..writeln();
    for (final i in pending) {
      out.writeln(switch (i) {
        ResolvedInstance(:final error?) =>
          '- `${i.path}` (${i.component}): o mapeamento não serve para esta instância: $error. Use o widget do DS'
              ' mais próximo e marque `f2d:inferred`.',
        ResolvedInstance(status: 'gap') =>
          '- `${i.path}` (${i.component}): componente do DS sem mapeamento. Use o widget do DS mais próximo e marque'
              ' `f2d:inferred`.',
        _ =>
          '- `${i.path}` (${i.component}): fora do DS. Placeholder, não substituir; brief de construção em'
              ' `${brief(i)}`.',
      });
    }
  }

  final sketches = s.components.where((c) => c.kind == 'sketch' || c.kind == 'local');
  if (sketches.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Componentes a montar (f2d:sketch, f2d:local)')
      ..writeln()
      ..writeln('Widgets que já existem (do DS ou do app), sem mapeamento campo a campo. Sempre montar: o `check` não')
      ..writeln('passa com o marcador.')
      ..writeln();
    for (final c in sketches) {
      out.writeln(
        '- [${c.name}](components/${c.folder}/BRIEF.md) → `${c.sketch!.widget!.name}`'
        '${c.kind == 'local' ? ' (do app)' : ''}',
      );
    }
  }

  final builds = s.components.where((c) => c.kind == 'build');
  if (builds.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Componentes a construir')
      ..writeln()
      ..writeln('Fora do DS. Só com a escolha do usuário; nessa ordem (dependências primeiro):')
      ..writeln();
    for (final c in builds) {
      out.writeln('- [${c.name}](components/${c.folder}/BRIEF.md) → `widgets/${c.folder}.dart`');
    }
  }

  out
    ..writeln()
    ..writeln('## Não fazer')
    ..writeln()
    ..writeln('- Não alterar widgets do DS nem criar variações deles; não usar cor ou espaçamento solto (só tokens).')
    ..writeln('- Não trocar placeholder de componente que o usuário não escolheu construir; não criar outros widgets.');
  if (s.text case final text?) {
    out.writeln('- Não usar `Text`/`TextStyle` do Flutter: texto é o widget do DS (`${oneLine(text)}`).');
  }
  for (final i in s.ignored) {
    out.writeln('- Não implementar `${i['path']}` (${i['component']}): ${i['reason']}.');
  }
  return out.toString();
}

/// A tarefa (pasta em `components/`) de uma instância: a de montar pelo mapeamento, o placeholder pela key.
ComponentTask? taskOf(ResolvedScreen s, ResolvedInstance i) => s.components
    .where(
      (c) => i.status == 'sketch' || i.status == 'local'
          ? c.sketch == i.mapping
          : c.sketch == null && c.key == i.componentKey,
    )
    .firstOrNull;

const _status = {
  'mapped': 'mapeado',
  'sketch': 'a montar',
  'local': 'do app, a montar',
  'gap': 'sem mapeamento',
  'placeholder': 'fora do DS',
};
