import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'resolve.dart';

/// A caixa [bounds] (unidades do Figma, relativa ao frame) com [margin] em volta, na escala da imagem ([scale]). Null
/// quando cai fora da imagem. O recorte do brief e o da revisão visual saem daqui.
img.Image? cropBox(img.Image image, Json bounds, num scale, {num margin = 0}) {
  int px(num v) => (v * scale).round();
  final x = px(max(0, (bounds['x']! as num) - margin)).clamp(0, image.width);
  final y = px(max(0, (bounds['y']! as num) - margin)).clamp(0, image.height);
  final width = min(px((bounds['width']! as num) + 2 * margin), image.width - x);
  final height = min(px((bounds['height']! as num) + 2 * margin), image.height - y);
  if (width <= 0 || height <= 0) return null;
  return img.copyCrop(image, x: x, y: y, width: width, height: height);
}

/// O recorte de uma instância do PNG da tela, em PNG (para o brief de montagem).
Uint8List? crop(img.Image screen, Json bounds, num scale) => switch (cropBox(screen, bounds, scale)) {
  final box? => img.encodePng(box),
  null => null,
};

/// O PNG cobre só o frame ([size] × [scale], ±1 px de arredondamento)? Sombra no frame ou filho saindo de um frame
/// sem recorte aumentam o PNG, e as caixas deixam de bater com os pixels. Sem [size] (IR sem tamanho), confia.
bool coversFrame(img.Image screen, Json? size, num scale) {
  bool near(int px, String key) => ((px - (size![key]! as num) * scale).abs()) <= 1;
  return size == null || (near(screen.width, 'width') && near(screen.height, 'height'));
}
