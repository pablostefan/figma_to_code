import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'mappings.dart';
import 'resolve.dart';

/// O que o plugin exporta: o `.zip` (`export.json` + PNGs) ou só o IR em `.json` (MCP).
class Export {
  Export(this.ir, [this._files = const {}]);

  final Json ir;
  final Map<String, Uint8List> _files;

  /// Um arquivo do zip (o PNG da tela, por exemplo); null fora do zip ou num export JSON.
  Uint8List? file(String path) => _files[path];

  static Export read(String path) {
    if (!path.toLowerCase().endsWith('.zip')) return Export(jsonDecode(File(path).readAsStringSync()) as Json);
    final files = {
      for (final f in ZipDecoder().decodeBytes(File(path).readAsBytesSync()))
        if (f.isFile) f.name: f.content,
    };
    final json = files['export.json'] ?? (throw ResolveError('$path não tem export.json: é um export do plugin?'));
    return Export(jsonDecode(utf8.decode(json)) as Json, files);
  }

  /// Copia para [dir] as imagens que os briefs citam, no mesmo caminho relativo do zip; devolve as copiadas.
  Set<String> copyImages(ResolvedScreen screen, Directory dir) {
    final copied = <String>{};
    final paths = {
      ?screen.image,
      for (final c in screen.components)
        for (final v in (c.definition?['variants'] as List? ?? const []).cast<Json>()) ?v['image'] as String?,
    };
    for (final path in paths) {
      // O caminho vem do export: não deixar escrever fora da pasta da tarefa.
      if (path.startsWith('/') || path.split('/').contains('..')) continue;
      final bytes = _files[path];
      if (bytes != null) {
        File('${dir.path}/$path')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        copied.add(path);
      }
    }
    return copied;
  }
}
