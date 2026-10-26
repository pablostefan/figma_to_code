/// Captura da tela para a revisão visual do figma2dart (`figma2dart review`). Só para testes:
/// `import 'package:figma_connect/capture.dart';` num teste de widget.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renderiza [app] no tamanho do frame do Figma, com as fontes do app, e grava em
/// `<tasks>/<task>/capture/` o `screen.png` e o `layout.json` (textos com o retângulo e os erros de layout).
///
/// [app] é a tela já com o que ela precisa para montar (tema do DS, `MaterialApp`, dados de exemplo do Figma).
/// [task] é a pasta da tarefa do `figma2dart resolve` (o `review.json` dela diz o tamanho do frame).
/// [prepare] deixa a tela no estado do Figma antes da captura (valor digitado, item selecionado): sem isso, botão
/// desabilitado ou campo vazio viram diferença que não é da tela.
///
/// ```dart
/// testWidgets('captura: Transferir', (tester) async {
///   await figmaCapture(
///     tester,
///     MaterialApp(theme: appTheme, home: TransferPage(...)),
///     task: 'transferir',
///     prepare: (tester) => tester.enterText(find.byType(TextField), '15000'),
///   );
/// });
/// ```
///
/// Erros de layout (overflow) não reprovam o teste: vão para o `layout.json`, para a revisão. Sem a tarefa (CI, outra
/// máquina), não faz nada: o teste pode ficar no repositório.
Future<void> figmaCapture(
  WidgetTester tester,
  Widget app, {
  required String task,
  Future<void> Function(WidgetTester tester)? prepare,
  String tasks = '.figma2dart/tasks',
}) async {
  final dir = '$tasks/$task';
  final input = File('$dir/review.json');
  // `.figma2dart/` não é versionado: na CI e em outra máquina não há tarefa. O teste passa sem capturar (no tamanho
  // padrão do teste a tela daria overflow falso).
  if (!input.existsSync()) {
    debugPrint('figmaCapture: sem ${input.path} (rode `figma2dart resolve` desta tela); nada capturado.');
    return;
  }
  final review = jsonDecode(input.readAsStringSync()) as Map<String, Object?>;
  final frame = review['frame']! as Map<String, Object?>;
  final size = Size((frame['width']! as num).toDouble(), (frame['height']! as num).toDouble());
  final scale = (review['imageScale'] as num? ?? 2).toDouble();

  await _loadFonts();
  tester.view
    ..physicalSize = size * scale
    ..devicePixelRatio = scale;
  addTearDown(tester.view.reset);

  // Overflow e afins viram dado da revisão, não falha do teste.
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString().split('\n').first.trim());
  final key = GlobalKey();
  try {
    Future<void> settle() async {
      try {
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 5),
        );
      } on FlutterError {
        // Animação que não termina (indicador de progresso): fica o quadro atual.
      }
    }

    await tester.pumpWidget(RepaintBoundary(key: key, child: app));
    await settle();
    if (prepare != null) {
      await prepare(tester);
      await settle();
    }
  } finally {
    FlutterError.onError = previous;
  }

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final png = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: scale);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  final texts = <Map<String, Object?>>[];
  void visit(RenderObject node) {
    // O que não aparece (placeholder do campo depois de digitar, rota de baixo) não é texto da tela.
    if ((node is RenderOffstage && node.offstage) ||
        (node is RenderOpacity && node.opacity == 0) ||
        (node is RenderAnimatedOpacity && node.opacity.value == 0)) {
      return;
    }
    final text = switch (node) {
      RenderParagraph() => node.text.toPlainText(includeSemanticsLabels: false, includePlaceholders: false),
      RenderEditable() => node.plainText, // o valor digitado num campo
      _ => null,
    };
    if (text != null && node is RenderBox && node.hasSize && !node.size.isEmpty) {
      final rect = MatrixUtils.transformRect(node.getTransformTo(boundary), Offset.zero & node.size);
      if (text.trim().isNotEmpty && rect.overlaps(Offset.zero & size)) {
        texts.add({
          'text': text,
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height,
          if (node is RenderParagraph && node.didExceedMaxLines) 'cut': true,
        });
      }
    }
    node.visitChildren(visit);
  }

  boundary.visitChildren(visit);

  Directory('$dir/capture').createSync(recursive: true);
  File('$dir/capture/screen.png').writeAsBytesSync(png!);
  File('$dir/capture/layout.json').writeAsStringSync(
    const JsonEncoder.withIndent(
      '  ',
    ).convert({'width': size.width, 'height': size.height, 'scale': scale, 'texts': texts, 'errors': errors}),
  );
}

var _fontsLoaded = false;

/// Todas as fontes do app (as do DS inclusive) pelo `FontManifest.json`: sem isso o teste desenha o texto como
/// caixas.
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final String source;
  try {
    source = await rootBundle.loadString('FontManifest.json');
  } on FlutterError {
    return; // pacote sem fontes declaradas
  }
  final manifest = jsonDecode(source) as List<Object?>;
  for (final family in manifest.cast<Map<String, Object?>>()) {
    final loader = FontLoader(family['family']! as String);
    for (final font in (family['fonts']! as List<Object?>).cast<Map<String, Object?>>()) {
      loader.addFont(rootBundle.load(font['asset']! as String));
    }
    await loader.load();
  }
}
