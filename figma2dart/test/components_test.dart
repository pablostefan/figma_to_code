import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:figma2dart/src/components.dart';
import 'package:figma2dart/src/mappings.dart';
import 'package:figma2dart/src/resolve.dart';
import 'package:figma2dart/src/workspace.dart';
import 'package:test/test.dart';

import 'commands_test.dart' show tempApp;

void main() {
  test('components: status pelas keys dos arquivos; --name traz props, PNG das variantes e instâncias de dentro', () {
    final keyA = 'a' * 40, keyB = 'b' * 40, keyC = 'c' * 40, keyD = 'd' * 40;
    // O pacote de mapeamentos: A anotado, B ignorado na política.
    final app = tempApp();
    File('${app.path}/lib/connect/ds_a.figma.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("@FigmaConnect(key: '$keyA', name: 'A')\n");
    File('${app.path}/lib/figma_policy.dart').writeAsStringSync("const p = FigmaPolicy(ignored: {'$keyB': 'x'});\n");

    Json component(String key, String name, {List<Json> variants = const []}) => {
      'id': '1:$name',
      'key': key,
      'name': name,
      'role': 'exported',
      'props': <String, Object?>{},
      'variants': variants,
    };
    final c = component(
      keyC,
      'Card',
      variants: [
        {
          'id': '2:1',
          'name': 'size=md',
          'props': {'size': 'md'},
          'image': 'images/card/size=md.png',
          'tree': {
            'id': '2:1',
            'type': 'COMPONENT',
            'name': 'size=md',
            'children': [
              {
                'id': '2:2',
                'type': 'FRAME',
                'name': 'trailing',
                'children': [
                  {
                    'id': '2:3',
                    'type': 'INSTANCE',
                    'name': 'Badge',
                    'instance': {
                      'componentName': 'Badge',
                      'props': {'label': 'Pix'},
                    },
                  },
                ],
              },
            ],
          },
        },
        {'id': '2:4', 'name': 'size=sm', 'props': {'size': 'sm'}, 'tree': {'id': '2:4', 'type': 'COMPONENT'}},
      ],
    )..['description'] = 'Cartão.';
    c['props'] = {
      'size': {
        'type': 'VARIANT',
        'default': 'md',
        'options': ['md', 'sm'],
      },
    };
    final ir = {
      'kind': 'library',
      'source': {'fileName': 'DS', 'pageName': 'Components'},
      'components': [component(keyA, 'A'), component(keyB, 'B'), c, component(keyD, '_Base')],
    };
    final zip = File('${app.path}/figma2dart-library-components.zip')
      ..writeAsBytesSync(
        ZipEncoder().encode(
          Archive()
            ..addFile(ArchiveFile.string('export.json', jsonEncode(ir)))
            ..addFile(ArchiveFile.bytes('images/card/size=md.png', [1, 2, 3])),
        ),
      );
    final ws = Workspace.find(app.path);

    final list = components(ws, [zip.path]);
    expect((list['total'], list['annotated'], list['pending']), (4, 1, 1));
    expect([for (final c in (list['components'] as List).cast<Json>()) c['status']], [
      'anotado',
      'ignorado',
      'falta',
      'só do Figma',
    ]);
    expect((list['components'] as List).first, containsPair('file', 'ds_a.figma.dart'));

    final card = components(ws, [zip.path], name: 'Card');
    expect((card['key'], card['status'], card['page'], card['description']), (keyC, 'falta', 'Components', 'Cartão.'));
    expect((card['props'] as Json)['size'], containsPair('options', ['md', 'sm']));
    final [md, sm] = (card['variants'] as List).cast<Json>();
    expect(File(md['image'] as String).readAsBytesSync(), [1, 2, 3]);
    expect(md['image'], endsWith('/.figma2dart/connect/card/size_md.png'));
    expect(sm.containsKey('image'), isFalse);
    expect(card['instances'], [
      {
        'path': 'trailing/Badge',
        'component': 'Badge',
        'props': {'label': 'Pix'},
      },
    ]);
    expect(components(ws, [zip.path], name: keyC)['name'], 'Card'); // pela key também
    expect(() => components(ws, [zip.path], name: 'Nada'), throwsA(isA<ResolveError>()));
  });
}
