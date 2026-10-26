import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/review.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'commands_test.dart' show mappingsDir, tempApp;
import 'resolve_test.dart' show instanceNode, screenWith;

Json text(String t, num x, num y, {num width = 60, num height = 20, bool cut = false}) => {
  'text': t,
  'x': x,
  'y': y,
  'width': width,
  'height': height,
  if (cut) 'cut': true,
};

void main() {
  test('fatos: ausente, fora de ordem, só no Flutter, cortado; ícone de fonte não é texto; repetidos contam', () {
    final facts = reviewFacts(
      ['Título', 'Saldo', 'Pix', 'Pix', 'Continuar'],
      [
        text('Continuar', 0, 0), // subiu para o topo
        text('Título', 0, 40),
        text('Pix', 0, 80),
        text('Pix', 0, 120, cut: true),
        text('', 300, 120), // Icon(Icons.chevron_right)
        text('Ana Souza', 0, 160),
      ],
      errors: ['A RenderFlex overflowed by 4 pixels on the bottom.'],
    );
    expect(facts['missing'], ['Saldo']);
    expect(facts['outOfOrder'], ['Continuar']);
    expect(facts['onlyFlutter'], ['Ana Souza']);
    expect(facts['cut'], ['Pix']);
    expect(facts['errors'], hasLength(1));
  });

  test('fora de ordem só quando ficou inteiramente acima (ou à esquerda na mesma faixa) de quem vinha antes', () {
    // Avatar à esquerda, centralizado entre nome e detalhe: não é ordem trocada.
    final contact = [
      ('AS', text('AS', 12, 25, width: 20, height: 17)),
      ('Ana Souza', text('Ana Souza', 56, 12)),
      ('Pix', text('Pix', 56, 34)),
    ];
    expect(outOfOrder(contact), isEmpty);
    // O botão que vinha no fim e subiu para o topo.
    expect(outOfOrder([...contact, ('Continuar', text('Continuar', 0, -40))]), ['Continuar']);
    // Lado a lado trocados na mesma faixa.
    expect(outOfOrder([('A', text('A', 100, 0)), ('B', text('B', 0, 0))]), ['B']);
  });

  test('ordem de leitura: na mesma linha (centro dentro da altura) da esquerda para a direita', () {
    final order = readingOrder([
      text('Pix · ana@email.com', 56, 34),
      text('Ana Souza', 56, 12),
      text('AS', 12, 20), // avatar centralizado na altura das duas linhas
    ]);
    expect(order.map((t) => t['text']), ['AS', 'Ana Souza', 'Pix · ana@email.com']);
  });

  test('resolve grava o review.json; review monta lado a lado, seções, fatos e o critério', () async {
    // Tela 100×100 (PNG 2x): um frame que embrulha tudo, com título, um componente local e um espaçador vazio.
    final local = {
      ...instanceNode(key: 'local-key', component: 'ContactItem', props: {'name': 'Ana'}, remote: false),
      'bounds': {'x': 10, 'y': 50, 'width': 80, 'height': 30},
    };
    (local['instance'] as Json)['content'] = [
      {'path': 'name', 'text': 'Ana'},
    ];
    // Anotação do designer (componente `_…`): no PNG do Figma, fora do código, fora da revisão.
    final note = instanceNode(key: 'note-key', component: '_Nota', props: {}, remote: false);
    (note['instance'] as Json)['content'] = [
      {'path': 'text', 'text': 'Conferir com o jurídico'},
    ];
    final ir = screenWith([
      {
        'id': '2:1',
        'type': 'FRAME',
        'name': 'content',
        'children': [
          {
            'id': '2:2',
            'type': 'TEXT',
            'name': 'title',
            'bounds': {'x': 10, 'y': 10, 'width': 80, 'height': 20},
            'text': {'characters': 'Título', 'style': 'heading/md'},
          },
          local,
          {'id': '2:3', 'type': 'FRAME', 'name': 'spacer'},
          note,
        ],
      },
    ]);
    final state = (((ir['screens'] as List).single as Json)['states'] as List).single as Json;
    (state['tree'] as Json)['size'] = {'width': 100, 'height': 100};
    state['image'] = 'images/screens/T.png';
    state['imageScale'] = 2;
    final app = tempApp(config: 'screens: lib/telas\n');
    File(
      '${app.path}/pubspec.yaml',
    ).writeAsStringSync('name: app\ndev_dependencies:\n  figma_connect:\n    path: ../fc\n');
    final figma = img.Image(width: 200, height: 200)..clear(img.ColorRgb8(240, 240, 240));
    final zip = File('${app.path}/figma2dart-screen-t.zip')
      ..writeAsBytesSync(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('export.json', jsonEncode({...ir, 'irVersion': '1.4.0'})))
            ..addFile(ArchiveFile.bytes('images/screens/T.png', img.encodePng(figma))),
        ),
      );
    final ws = Workspace.find(app.path);
    final task = ((await resolveTasks(ws, zip, mappings: mappingsDir))['tasks'] as List).single as Json;

    final input = jsonDecode(File('${task['dir']}/review.json').readAsStringSync()) as Json;
    expect(input['frame'], {'width': 100, 'height': 100});
    expect(input['texts'], ['Título', 'Ana']); // sem o texto da anotação
    final sections = (input['sections'] as List).cast<Json>();
    expect(sections.map((s) => s['name']), ['title', 'ContactItem']); // dentro do `content`, sem espaçador e anotação
    expect(sections.last['structure'], contains('componente local **ContactItem**'));

    // Sem captura: diz qual teste escrever (o figma_connect já está nas dev_dependencies: nada a adicionar).
    final missing = review(ws, 'T');
    expect(missing['capture'], isFalse);
    expect(missing['testFile'], '${ws.app}/test/telas/t_figma_test.dart');
    expect(missing['test'], contains("task: 't'"));
    expect(missing.containsKey('devDependency'), isFalse);

    // Captura feita à mão (o que o figmaCapture grava): o local subiu acima do título.
    Directory('${task['dir']}/capture').createSync();
    File('${task['dir']}/capture/screen.png').writeAsBytesSync(img.encodePng(img.Image(width: 200, height: 200)));
    File('${task['dir']}/capture/layout.json').writeAsStringSync(
      jsonEncode({
        'width': 100,
        'height': 100,
        'scale': 2,
        'texts': [text('Ana', 10, 5), text('Título', 10, 40)],
        'errors': <String>[],
      }),
    );
    final r = review(ws, 'T');
    final screen = img.decodePng(File(r['screen'] as String).readAsBytesSync())!;
    expect((screen.width, screen.height), (100 + 16 + 100, 32 + 100)); // 1x, lado a lado, com o rótulo
    expect(r['sections'], hasLength(2));
    final pair = img.decodePng(File((r['sections'] as List).first as String).readAsBytesSync())!;
    expect(pair.width, 2 * (80 + 16) * 2 + 16); // caixa + 8 de margem dos dois lados, em 2x, Figma | Flutter
    expect(r['facts'], containsPair('outOfOrder', 1));

    final md = File(r['review'] as String).readAsStringSync();
    expect(md, contains('## Critério'));
    expect(md, contains('**Ignorar**'));
    expect(md, contains('Base obrigatória'));
    expect(md, contains('- Texto fora da ordem do Figma: "Ana"')); // o que subiu
    expect(md, contains('### 2. `ContactItem` → `sections/02-contact_item.png`'));
    expect(md, contains('## Só do Figma (não implementar)'));
    expect(md, contains('_Nota'));

    // PNG do Figma maior que o frame (sombra): as caixas não batem com ele; só a tela inteira.
    File('${task['dir']}/images/screens/T.png').writeAsBytesSync(img.encodePng(img.Image(width: 240, height: 220)));
    final shadow = review(ws, 'T');
    expect(shadow['sections'], isEmpty);
    expect(File(shadow['review'] as String).readAsStringSync(), contains('**Sem recorte por seção:**'));
  });

  test('review acha a tarefa pelo nome exato da tela, não pelo nome base (07 · Sucesso ≠ 05 · Sucesso)', () {
    final app = tempApp();
    File(
      '${app.path}/pubspec.yaml',
    ).writeAsStringSync('name: app\ndev_dependencies:\n  figma_connect:\n    path: ../fc\n');
    final ws = Workspace.find(app.path);
    for (final (folder, screen) in [('sucesso', '05 · Sucesso'), ('sucesso_9_999', '07 · Sucesso')]) {
      File('${ws.tasks}/$folder/review.json')
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'screen': screen}));
    }
    expect(review(ws, '07 · Sucesso')['task'], 'sucesso_9_999');
    expect(review(ws, '05 · Sucesso')['task'], 'sucesso');
  });
}
