import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'resolve.dart';

/// Recorta do PNG da tela a caixa de uma instância ([bounds], em unidades do Figma relativas ao frame), na escala do
/// PNG ([scale]). Null quando a caixa cai fora da imagem.
Uint8List? crop(img.Image screen, Json bounds, num scale) {
  int px(String key) => ((bounds[key]! as num) * scale).round();
  final x = px('x').clamp(0, screen.width);
  final y = px('y').clamp(0, screen.height);
  final width = min(px('width'), screen.width - x);
  final height = min(px('height'), screen.height - y);
  if (width <= 0 || height <= 0) return null;
  return img.encodePng(img.copyCrop(screen, x: x, y: y, width: width, height: height));
}

/// O PNG cobre só o frame ([size] × [scale], ±1 px de arredondamento)? Sombra no frame ou filho saindo de um frame
/// sem recorte aumentam o PNG, e as caixas deixam de bater com os pixels. Sem [size] (IR sem tamanho), confia.
bool coversFrame(img.Image screen, Json? size, num scale) {
  bool near(int px, String key) => ((px - (size![key]! as num) * scale).abs()) <= 1;
  return size == null || (near(screen.width, 'width') && near(screen.height, 'height'));
}
