import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:figma2dart/src/commands.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

import 'commands_test.dart' show mappingsDir, tempApp;
import 'resolve_test.dart' show instanceNode, screenWith, statementKey;

/// Resolve uma tela 100×100 (em 2x) com um sketch em (10,20) 30×40 e o PNG [screen]; devolve a pasta do componente,
/// o nome do recorte e o brief.
Future<({String dir, String crop, String md})> _resolve(img.Image screen) async {
  final template = instanceNode(key: statementKey, component: 'Template / Extrato', props: {'title': 'Extrato'});
  final ir = screenWith([
    {
      ...template,
      'bounds': {'x': 10, 'y': 20, 'width': 30, 'height': 40},
      'instance': {
        ...template['instance'] as Json,
        'content': [
          {'path': 'days/Hoje', 'text': 'Hoje'},
          {
            'path': 'days/Row',
            'component': 'TransactionItem',
            'props': {'title': 'Mercado', 'amount': '-R\$ 45,90'},
          },
        ],
      },
    },
  ]);
  final state = (((ir['screens'] as List).single as Json)['states'] as List).single as Json;
  state['image'] = 'images/screens/T.png';
  state['imageScale'] = 2;
  (state['tree'] as Json)['size'] = {'width': 100, 'height': 100};

  final app = tempApp(config: 'screens: lib/telas\n');
  final zip = File('${app.path}/figma2dart-screen-t.zip')
    ..writeAsBytesSync(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('export.json', jsonEncode({...ir, 'irVersion': '1.3.0'})))
          ..addFile(ArchiveFile.bytes('images/screens/T.png', img.encodePng(screen))),
      ),
    );
  final ws = Workspace.find(app.path);
  final task = ((await resolveTasks(ws, zip, mappings: mappingsDir))['tasks'] as List).single as Json;
  return (
    dir: '${app.path}/.figma2dart/tasks/t/components/template_extrato',
    crop: '${(template['id'] as String).replaceAll(':', '-')}.png',
    md: File('${(task['components'] as List).cast<Json>().single['brief']}').readAsStringSync(),
  );
}

void main() {
  test('sketch na tela: recorte do PNG pela caixa da instância e o conteúdo de dentro no brief', () async {
    // Tela 100×100 em 2x (PNG 200×200), branca; a instância ocupa (10,20) 30×40 no Figma e está pintada de vermelho.
    final screen = img.Image(width: 200, height: 200)..clear(img.ColorRgb8(255, 255, 255));
    img.fillRect(screen, x1: 20, y1: 40, x2: 79, y2: 119, color: img.ColorRgb8(255, 0, 0));
    final (:dir, :crop, :md) = await _resolve(screen);

    final cropped = img.decodePng(File('$dir/$crop').readAsBytesSync())!;
    expect((cropped.width, cropped.height), (60, 80)); // 30×40 em 2x
    expect(cropped.getPixel(30, 40).r, 255); // só o pedaço vermelho
    expect(cropped.getPixel(30, 40).g, 0);

    expect(md, contains('- Recorte do Figma: `$crop` (nesta pasta)'));
    expect(md, contains('- Conteúdo dentro da instância, como está no Figma:'));
    expect(md, contains('  - `days/Hoje`: "Hoje"'));
    expect(md, contains('  - `days/Row`: TransactionItem `{"title":"Mercado","amount":"-R\$ 45,90"}`'));
    expect(md, isNot(contains('Instâncias expostas'))); // o conteúdo já as mostra
  });

  test('PNG maior que o frame (sombra, filho para fora): sem recorte, para não mostrar o pedaço errado', () async {
    final (:dir, :crop, :md) = await _resolve(img.Image(width: 240, height: 220));
    expect(File('$dir/$crop').existsSync(), isFalse);
    expect(md, isNot(contains('Recorte do Figma')));
    expect(md, contains('Conteúdo dentro da instância')); // o resto do brief continua
  });

  test('IR 1.2 (sem caixa nem conteúdo) continua resolvendo, sem recorte', () async {
    final app = tempApp(config: 'screens: lib/telas\n');
    final node = instanceNode(key: statementKey, component: 'Template / Extrato', props: {'title': 'E'});
    (node['instance'] as Json)['exposed'] = [
      {
        'path': 'header',
        'componentName': 'Badge',
        'componentKey': 'k',
        'props': {'label': 'Novo'},
      },
    ];
    final ir = screenWith([node]);
    final export = File('${app.path}/export.json')..writeAsStringSync(jsonEncode(ir));
    final task =
        ((await resolveTasks(Workspace.find(app.path), export, mappings: mappingsDir))['tasks'] as List).single as Json;
    final md = File('${(task['components'] as List).cast<Json>().single['brief']}').readAsStringSync();
    expect(md, isNot(contains('Recorte do Figma')));
    expect(md, isNot(contains('Conteúdo dentro da instância')));
    expect(md, contains('- Instâncias expostas:\n  - `header`: Badge `{"label":"Novo"}`'));
  });
}
