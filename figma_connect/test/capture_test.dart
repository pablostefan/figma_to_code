import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:figma_connect/capture.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captura: PNG no tamanho do frame × escala, textos com o retângulo e overflow sem reprovar', (
    tester,
  ) async {
    final tasks = Directory.systemTemp.createTempSync('figma_capture').path;
    var prepared = false;
    Directory('$tasks/t').createSync();
    File('$tasks/t/review.json').writeAsStringSync(
      jsonEncode({
        'frame': {'width': 100, 'height': 80},
        'imageScale': 2,
      }),
    );

    await figmaCapture(
      tester,
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Olá'),
            Row(children: [SizedBox(width: 150, height: 10)]), // 50 a mais que o frame
          ],
        ),
      ),
      task: 't',
      tasks: tasks,
      prepare: (tester) async => prepared = true,
    );
    expect(prepared, isTrue);

    final png = File('$tasks/t/capture/screen.png').readAsBytesSync();
    final header = ByteData.sublistView(png, 16, 24);
    expect((header.getUint32(0), header.getUint32(4)), (200, 160));

    final layout = jsonDecode(File('$tasks/t/capture/layout.json').readAsStringSync()) as Map<String, Object?>;
    final [text] = (layout['texts']! as List<Object?>).cast<Map<String, Object?>>();
    expect(text['text'], 'Olá');
    expect((text['x'], text['y']), (0, 0));
    expect(layout['errors'], [contains('overflowed by 50')]);
  });
}
