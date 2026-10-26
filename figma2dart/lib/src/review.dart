import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

import 'brief.dart';
import 'commands.dart' show ensureFigmaConnect;
import 'crop.dart';
import 'mappings.dart' show ResolveError;
import 'names.dart';
import 'resolve.dart';
import 'structure.dart';
import 'workspace.dart';

/// Revisão visual: a LLM compara o que o Flutter renderizou com o Figma, com um critério do que importa. A CLI dá o
/// material (imagens lado a lado, fatos sem pixel, a estrutura de cada seção), não o veredito: diferença de ambiente
/// (fonte, serrilhado) nunca vira número aqui.

/// O que a captura (`figmaCapture`) e o `review` precisam da tela; o `resolve` grava em `review.json` na tarefa.
Json reviewInput(ResolvedScreen s, {required Set<String> images}) {
  final size = s.tree['size'] as Json? ?? const {};
  final resolved = {for (final i in s.instances) i.id: i};
  // Instância que o resolvedor pulou (anotação do designer, `_`/`.`, ignorada pela política): não entra no código,
  // então não entra nos fatos nem nas seções; o REVIEW.md a lista para o revisor não cobrar.
  bool ignored(Json n) => n['instance'] != null && !resolved.containsKey(n['id']);
  String link(ResolvedInstance i) => '../components/${taskOf(s, i)?.folder}/BRIEF.md';
  String structure(Json node) {
    final out = StringBuffer();
    writeStructure(out, node, resolved, link); // código do DS na linha: a base fica à mão
    return out.toString().trimRight();
  }

  return {
    'screen': s.screen,
    'frame': {'width': size['width'], 'height': size['height']},
    'imageScale': s.imageScale,
    'image': images.contains(s.image) ? s.image : null,
    'texts': figmaTexts(s.tree, skip: ignored),
    'ignored': [for (final i in s.ignored) '${i['path']} (${i['component']})'],
    'sections': [
      for (final node in sections(s.tree, skip: ignored))
        {'name': node['name'], 'id': node['id'], 'bounds': ?node['bounds'], 'structure': structure(node)},
    ],
  };
}

/// Textos visíveis da tela na ordem das camadas (a de leitura num layout automático), com os de dentro das
/// instâncias (`content`, IR 1.3).
List<String> figmaTexts(Json node, {bool Function(Json node)? skip}) => [
  if (node['visible'] != false && !(skip?.call(node) ?? false)) ...[
    if (node['text'] case {'characters': final String text}) text,
    for (final item in ((node['instance'] as Json?)?['content'] as List? ?? const []).cast<Json>())
      if (item['text'] case final String text) text,
    for (final child in (node['children'] as List? ?? const []).cast<Json>()) ...figmaTexts(child, skip: skip),
  ],
];

/// Seções da tela: os filhos visíveis do frame (ou do frame único que embrulha tudo), sem os vazios (espaçador) e
/// sem o que [skip] diz.
List<Json> sections(Json root, {bool Function(Json node)? skip}) {
  List<Json> visible(Json n) => [
    for (final c in (n['children'] as List? ?? const []).cast<Json>())
      if (c['visible'] != false && !(skip?.call(c) ?? false)) c,
  ];
  var node = root;
  for (var kids = visible(node); kids.length == 1 && kids.single['instance'] == null; kids = visible(node)) {
    if (kids.single['children'] == null) break;
    node = kids.single;
  }
  return [
    for (final c in visible(node))
      if (c['children'] != null || c['text'] != null || c['instance'] != null) c,
  ];
}

/// `figma2dart review --screen <tela>`: lê a tarefa (`review.json`, o PNG do Figma) e a captura (`capture/`), grava
/// `review/` com `screen.png` (Figma | Flutter), um par por seção, `facts.json` e o `REVIEW.md` com o critério.
Json review(Workspace ws, String screen) {
  // Pelo nome exato da tela primeiro: "07 · Sucesso" resolvida junto com "05 · Sucesso" fica em `sucesso_<id>`, e
  // pelo nome base cairia na tarefa da outra.
  String? screenOf(Directory d) => switch (File('${d.path}/review.json')) {
    final f when f.existsSync() => (jsonDecode(f.readAsStringSync()) as Json)['screen'] as String?,
    _ => null,
  };
  final tasks = Directory(ws.tasks);
  final dir =
      (tasks.existsSync() ? tasks.listSync().whereType<Directory>() : const <Directory>[])
          .where((d) => screenOf(d) == screen)
          .firstOrNull ??
      ['${ws.tasks}/${screenSlug(screen)}', '${ws.tasks}/$screen']
          .map(Directory.new)
          .firstWhere(
            (d) => d.existsSync(),
            orElse: () => throw ResolveError(
              'Tarefa "$screen" não encontrada em ${ws.tasks}: rode `figma2dart resolve` desta tela.',
            ),
          );
  final inputFile = File('${dir.path}/review.json');
  if (!inputFile.existsSync()) throw ResolveError('${inputFile.path} não existe: rode o `resolve` desta tela de novo.');
  final input = jsonDecode(inputFile.readAsStringSync()) as Json;
  final task = dir.uri.pathSegments.where((p) => p.isNotEmpty).last;
  final capture = File('${dir.path}/capture/screen.png');
  final layoutFile = File('${dir.path}/capture/layout.json');
  // Sem captura: prepara (figma_connect nas dev_dependencies) e diz qual teste escrever; depois, `review` de novo.
  if (!capture.existsSync() || !layoutFile.existsSync()) {
    final screens = ws.screens?.replaceFirst(RegExp('^lib/?'), '') ?? 'figma';
    return {
      'capture': false,
      'task': task,
      'testFile': '${ws.app}/test/${screens.isEmpty ? '' : '$screens/'}${task}_figma_test.dart',
      'test': captureTest(input['screen'] as String, task),
      'devDependency': ?ensureFigmaConnect(ws, ws.app),
    };
  }
  final layout = jsonDecode(layoutFile.readAsStringSync()) as Json;
  final figmaPng = switch (input['image']) {
    final String path when File('${dir.path}/$path').existsSync() => img.decodePng(
      File('${dir.path}/$path').readAsBytesSync(),
    ),
    _ => null,
  };
  if (figmaPng == null) throw ResolveError('A tarefa não tem o PNG da tela do Figma (export sem imagens).');
  final flutterPng = img.decodePng(capture.readAsBytesSync())!;

  final out = Directory('${dir.path}/review');
  if (out.existsSync()) out.deleteSync(recursive: true);
  Directory('${out.path}/sections').createSync(recursive: true);

  final frame = input['frame'] as Json;
  final width = (frame['width'] as num).round();
  File('${out.path}/screen.png').writeAsBytesSync(
    img.encodePng(sideBySide(img.copyResize(figmaPng, width: width), img.copyResize(flutterPng, width: width))),
  );

  final figmaScale = input['imageScale'] as num? ?? 2;
  final flutterScale = layout['scale'] as num? ?? figmaScale;
  // PNG do Figma maior que o frame (sombra, filho para fora sem recorte): a caixa da seção não bate com os pixels
  // dele; par deslocado gera achado falso. Fica só a tela inteira.
  final aligned = coversFrame(figmaPng, frame, figmaScale);
  final sectionFiles = <String?>[];
  for (final (n, section) in (input['sections'] as List).cast<Json>().indexed) {
    final bounds = section['bounds'] as Json?;
    final a = bounds == null || !aligned ? null : cropBox(figmaPng, bounds, figmaScale, margin: 8);
    var b = a == null ? null : cropBox(flutterPng, bounds!, flutterScale, margin: 8);
    if (a == null || b == null) {
      sectionFiles.add(null);
      continue;
    }
    if (b.width != a.width || b.height != a.height) b = img.copyResize(b, width: a.width, height: a.height);
    final name = 'sections/${'${n + 1}'.padLeft(2, '0')}-${snakeCase('${section['name']}')}.png';
    File('${out.path}/$name').writeAsBytesSync(img.encodePng(sideBySide(a, b)));
    sectionFiles.add(name);
  }

  final facts = reviewFacts(
    (input['texts'] as List).cast<String>(),
    (layout['texts'] as List).cast<Json>(),
    errors: (layout['errors'] as List? ?? const []).cast<String>(),
  );
  const json = JsonEncoder.withIndent('  ');
  File('${out.path}/facts.json').writeAsStringSync(json.convert(facts));
  File('${out.path}/REVIEW.md').writeAsStringSync(reviewMarkdown(input, facts, sectionFiles, aligned: aligned));
  return {
    'dir': out.absolute.path,
    'review': '${out.absolute.path}/REVIEW.md',
    'screen': '${out.absolute.path}/screen.png',
    'sections': [for (final f in sectionFiles.nonNulls) '${out.absolute.path}/$f'],
    'facts': {for (final MapEntry(:key, :value) in facts.entries) key: (value as List).length},
  };
}

/// O teste de captura que a LLM completa: só ela sabe montar a tela (construtor, tema, dados do Figma).
String captureTest(String screen, String task) =>
    '''
import 'package:figma_connect/capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('figma: $screen', (tester) async {
    // A tela com o tema do app e os dados de exemplo do Figma (textos, listas), sem back-end.
    await figmaCapture(tester, /* MaterialApp(theme: …, home: Tela(…)) */, task: '$task');
  });
}
''';

/// Figma à esquerda, Flutter à direita, com o rótulo em cima.
img.Image sideBySide(img.Image figma, img.Image flutter) {
  const gap = 16, header = 32;
  final out = img.Image(width: figma.width + gap + flutter.width, height: header + max(figma.height, flutter.height))
    ..clear(img.ColorRgb8(255, 255, 255));
  img.drawString(out, 'Figma', font: img.arial24, x: 4, y: 4, color: img.ColorRgb8(0, 0, 0));
  img.drawString(out, 'Flutter', font: img.arial24, x: figma.width + gap + 4, y: 4, color: img.ColorRgb8(0, 0, 0));
  img.compositeImage(out, figma, dstX: 0, dstY: header);
  img.compositeImage(out, flutter, dstX: figma.width + gap, dstY: header);
  return out;
}

/// Fatos que não dependem de pixel, como pista para o revisor (ele confirma na imagem): textos do Figma que não
/// apareceram, os que apareceram fora da ordem, os que só o Flutter tem (podem ser dado), os cortados e os erros de
/// layout da captura.
Json reviewFacts(List<String> figma, List<Json> flutter, {List<String> errors = const []}) {
  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
  final a = figma.map(norm).where((t) => t.isNotEmpty).toList();
  final shown = readingOrder(flutter.where((t) => !_icon(t['text'] as String)).toList());
  final b = shown.map((t) => norm(t['text'] as String)).toList();

  final available = <String, int>{};
  for (final t in b) {
    available[t] = (available[t] ?? 0) + 1;
  }
  final missing = <String>[];
  for (final t in a) {
    if ((available[t] ?? 0) > 0) {
      available[t] = available[t]! - 1;
    } else {
      missing.add(t);
    }
  }
  final remaining = {for (final t in a) t: 0};
  for (final t in a) {
    remaining[t] = remaining[t]! + 1;
  }
  final onlyFlutter = <String>[];
  for (final t in b) {
    if ((remaining[t] ?? 0) > 0) {
      remaining[t] = remaining[t]! - 1;
    } else {
      onlyFlutter.add(t);
    }
  }
  // Cada texto do Figma com o seu no Flutter (o k-ésimo "Pix" com o k-ésimo "Pix", na ordem de leitura).
  final pool = <String, List<Json>>{};
  for (final (i, t) in b.indexed) {
    (pool[t] ??= []).add(shown[i]);
  }
  final matched = <(String, Json)>[
    for (final t in a)
      if (pool[t]?.isNotEmpty ?? false) (t, pool[t]!.removeAt(0)),
  ];
  return {
    'missing': missing,
    'outOfOrder': outOfOrder(matched),
    'onlyFlutter': onlyFlutter,
    'cut': [
      for (final t in shown)
        if (t['cut'] == true) norm(t['text'] as String),
    ],
    'errors': errors,
  };
}

/// Ordem de leitura: de cima para baixo; na mesma linha (o centro de um dentro da altura do outro), da esquerda
/// para a direita.
List<Json> readingOrder(List<Json> texts) {
  num top(Json t) => t['y'] as num;
  num center(Json t) => top(t) + (t['height'] as num) / 2;
  final rows = <List<Json>>[];
  for (final t in [...texts]..sort((a, b) => top(a).compareTo(top(b)))) {
    final row = rows.lastOrNull;
    if (row != null && center(t) <= top(row.first) + (row.first['height'] as num)) {
      row.add(t);
    } else {
      rows.add([t]);
    }
  }
  return [for (final row in rows) ...row..sort((a, b) => (a['x'] as num).compareTo(b['x'] as num))];
}

/// Ícone de fonte (`Icon`) é um parágrafo com um caractere da área privada do Unicode: não é texto.
bool _icon(String text) =>
    text.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || String.fromCharCode(r).trim().isEmpty);

/// Textos fora da ordem do Figma ([matched]: na ordem do Figma, cada um com o retângulo no Flutter). Só conta quem
/// ficou **inteiramente acima** de um que vinha antes (ou inteiramente à esquerda, na mesma faixa): avatar ao lado
/// do nome não é ordem trocada. Sai primeiro quem tem mais inversões (empate: o que vinha depois no Figma, o que
/// "subiu").
List<String> outOfOrder(List<(String, Json)> matched) {
  num top(Json t) => t['y'] as num;
  num bottom(Json t) => top(t) + (t['height'] as num);
  num left(Json t) => t['x'] as num;
  num right(Json t) => left(t) + (t['width'] as num);
  // [later] (depois no Figma) aparece antes de [earlier] no Flutter?
  bool before(Json later, Json earlier) =>
      bottom(later) <= top(earlier) + 2 ||
      (bottom(later) > top(earlier) && top(later) < bottom(earlier) && right(later) <= left(earlier) + 2);
  final alive = {for (var i = 0; i < matched.length; i++) i};
  final out = <int>[];
  while (true) {
    final count = {for (final i in alive) i: 0};
    for (final i in alive) {
      for (final j in alive) {
        if (i < j && before(matched[j].$2, matched[i].$2)) {
          count[i] = count[i]! + 1;
          count[j] = count[j]! + 1;
        }
      }
    }
    final worst = count.entries
        .where((e) => e.value > 0)
        .fold<MapEntry<int, int>?>(
          null,
          (best, e) => best == null || e.value > best.value || (e.value == best.value && e.key > best.key) ? e : best,
        );
    if (worst == null) break;
    alive.remove(worst.key);
    out.add(worst.key);
  }
  return [for (final i in out..sort()) matched[i].$1];
}

/// O `REVIEW.md`: o critério (o que importa, o que ignorar), as regras do revisor, os fatos e cada seção com a
/// estrutura do brief (a base dos achados).
String reviewMarkdown(Json input, Json facts, List<String?> sectionFiles, {bool aligned = true}) {
  final out = StringBuffer()
    ..writeln('# Revisão visual: ${input['screen']}')
    ..writeln()
    ..writeln('Compare o que o Flutter renderizou com o Figma e devolva **até 5 achados**, os mais graves primeiro.')
    ..writeln('A tela nunca fica igual pixel a pixel: o que importa é o que uma pessoa usando o app notaria.')
    ..writeln()
    ..writeln('Imagens nesta pasta (Figma à esquerda, Flutter à direita):')
    ..writeln()
    ..writeln('- `screen.png`: a tela inteira, na mesma escala. É a referência para ordem e conjunto.')
    ..writeln(
      '- `sections/`: cada seção recortada **na caixa do Figma**, nos dois lados. Se o layout do Flutter deslocou, o',
    )
    ..writeln('  recorte do lado direito mostra outra coisa: confira na tela inteira antes de concluir.')
    ..writeln()
    ..write(
      aligned
          ? ''
          : '**Sem recorte por seção:** o PNG do Figma é maior que o frame (sombra ou conteúdo para fora), as caixas não '
                'batem com ele. Compare pela tela inteira.\n\n',
    )
    ..writeln('## Critério')
    ..writeln()
    ..writeln('| Nível | O quê |')
    ..writeln('|---|---|')
    ..writeln(
      '| **Importa** | elemento faltando ou sobrando; ordem trocada; componente errado; cor de fundo, destaque ou texto '
      'trocada; ícone errado ou na direção errada; alinhamento trocado (centro × esquerda); hierarquia de texto '
      'invertida; texto cortado que o Figma não corta; overflow |',
    )
    ..writeln(
      '| **Talvez** | espaçamento claramente diferente a olho (meio gap ou mais); tamanho de componente visivelmente '
      'diferente |',
    )
    ..writeln(
      '| **Ignorar** | renderização de fonte e serrilhado; sombra sutil; diferença de 1–3 px; status bar e área '
      'segura; dado diferente do exemplo do Figma (nome maior, mais itens); placeholders `f2d` e imagens '
      '`TODO(f2d)` |',
    )
    ..writeln()
    ..writeln('## Regras')
    ..writeln()
    ..writeln(
      '- **Base obrigatória:** cada achado cita a linha da estrutura abaixo (ou do brief) que diz como deve ser. Sem',
    )
    ..writeln('  base, não é achado.')
    ..writeln('- "Ignorar" não aparece na resposta. "Talvez" só com o valor do Figma em mãos.')
    ..writeln('- Os fatos abaixo são pista: confirme na imagem antes de relatar.')
    ..writeln(
      '- Estado diferente (botão desabilitado, campo vazio ou em foco, item selecionado) costuma vir do teste de captura',
    )
    ..writeln(
      '  sem o estado do Figma: relate como "Talvez" com a correção "ajustar o `prepare` do teste", não a tela.',
    )
    ..writeln('- Termine sem achados se não houver nada do nível "Importa" ou "Talvez": não force.')
    ..writeln()
    ..writeln('Resposta, um item por achado:')
    ..writeln()
    ..writeln('```')
    ..writeln('[Importa|Talvez] <seção> — <o que está diferente>')
    ..writeln('  Figma: <como está> · Flutter: <como ficou>')
    ..writeln('  Base: <linha da estrutura ou do brief>')
    ..writeln('  Correção: <o que mudar no código, com o token ou widget do brief>')
    ..writeln('```')
    ..writeln()
    ..writeln('## Fatos (sem pixel)')
    ..writeln();
  void fact(String key, String label) {
    final list = (facts[key] as List).cast<String>();
    out.writeln('- $label: ${list.isEmpty ? 'nenhum' : list.map(jsonEncode).join(', ')}');
  }

  fact('missing', 'Texto do Figma que não apareceu (pode vir de dado)');
  fact('outOfOrder', 'Texto fora da ordem do Figma');
  fact('onlyFlutter', 'Texto só no Flutter (dado de exemplo?)');
  fact('cut', 'Texto cortado no Flutter');
  fact('errors', 'Erro de layout na captura');
  if ((input['ignored'] as List? ?? const []).cast<String>() case final ignored when ignored.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Só do Figma (não implementar)')
      ..writeln()
      ..writeln('Aparecem no PNG do Figma e não entram no código (anotação, marcação): não são "elemento faltando".')
      ..writeln();
    for (final i in ignored) {
      out.writeln('- `$i`');
    }
  }
  out
    ..writeln()
    ..writeln('## Seções')
    ..writeln();
  for (final (n, section) in (input['sections'] as List).cast<Json>().indexed) {
    final file = sectionFiles[n];
    out
      ..writeln(
        '### ${n + 1}. `${section['name']}`${file == null ? ' (sem recorte: veja a tela inteira)' : ' → `$file`'}',
      )
      ..writeln()
      ..writeln(section['structure'])
      ..writeln();
  }
  return out.toString();
}
