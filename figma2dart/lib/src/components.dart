import 'dart:io';

import 'commands.dart';
import 'export.dart';
import 'mappings.dart';
import 'names.dart';
import 'resolve.dart';
import 'workspace.dart';

final _key = RegExp('[0-9a-f]{40}');

/// Componentes do DS (exports do plugin em modo biblioteca) × anotações do pacote de mapeamentos: o que falta anotar
/// e, com [name] (nome ou key), o que é preciso para anotar um. Para o agente que escreve as anotações: a key e as
/// props vêm daqui (o MCP local do Figma não dá a key).
///
/// O status vem das keys escritas nos arquivos (`lib/connect/` anotados, `lib/figma_policy.dart` ignorados), sem o
/// analyzer: rápido, e funciona com uma anotação que ainda não compila.
Json components(Workspace ws, List<String> files, {String? name}) {
  final package = ws.mappings()?.path ?? ws.app;
  final annotated = <String, String>{};
  final connect = Directory('$package/lib/connect');
  if (connect.existsSync()) {
    for (final file in connect.listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final key in _key.allMatches(file.readAsStringSync())) {
        annotated[key[0]!] = file.uri.pathSegments.last;
      }
    }
  }
  final policy = File('$package/lib/figma_policy.dart');
  final ignored = policy.existsSync()
      ? {for (final k in _key.allMatches(policy.readAsStringSync())) k[0]!}
      : const <String>{};

  String status(Json c) => switch (c['key']) {
    final String key when annotated.containsKey(key) => 'anotado',
    final String key when ignored.contains(key) => 'ignorado',
    _ when '${c['name']}'.startsWith('_') || '${c['name']}'.startsWith('.') => 'só do Figma',
    _ => 'falta',
  };

  final all = <(Json, String, Export)>[];
  final paths = libraryExports(ws, files);
  for (final path in paths) {
    final export = Export.read(path);
    if (export.ir['kind'] != 'library') {
      throw ResolveError(
        '$path é um export de ${export.ir['kind']}, não de biblioteca: no plugin, exporte a página do DS sem seleção.',
      );
    }
    final page = '${(export.ir['source'] as Json)['pageName']}';
    for (final c in (export.ir['components'] as List).cast<Json>()) {
      all.add((c, page, export));
    }
  }

  if (name != null) {
    final (c, page, export) =
        all.where((e) => e.$1['name'] == name || e.$1['key'] == name).firstOrNull ??
        (throw ResolveError('Componente "$name" não está em ${paths.join(', ')}.'));
    return {
      ...detail(c, export, Directory('${ws.app}/.figma2dart/connect/${snakeCase('${c['name']}')}')),
      'page': page,
      'status': status(c),
      if (annotated[c['key']] case final file?) 'file': file,
    };
  }
  final list = [
    for (final (c, page, _) in all)
      {
        'name': c['name'],
        'key': c['key'],
        'page': page,
        'variants': (c['variants'] as List).length,
        'status': status(c),
        if (annotated[c['key']] case final file?) 'file': file,
      },
  ];
  int count(String s) => list.where((c) => c['status'] == s).length;
  return {
    'exports': paths,
    'mappings': package,
    'total': list.length,
    'annotated': count('anotado'),
    'pending': count('falta'),
    'components': list,
  };
}

/// Um componente para anotar: props do Figma, cada variante com o PNG (gravado em [dir]) e as instâncias de dentro
/// da primeira variante, com o caminho (o de `f.nested`/`f.instance`) e as props.
Json detail(Json c, Export export, Directory dir) {
  final variants = (c['variants'] as List).cast<Json>();
  final instances = <Json>[];
  void walk(Json node, String path) {
    for (final child in (node['children'] as List? ?? const []).cast<Json>()) {
      final childPath = path.isEmpty ? '${child['name']}' : '$path/${child['name']}';
      if (child['instance'] case final Json i) {
        instances.add({'path': childPath, 'component': i['componentName'], 'props': i['props']});
      } else {
        walk(child, childPath);
      }
    }
  }

  if (variants.isNotEmpty) walk(variants.first['tree'] as Json, '');
  return {
    'name': c['name'],
    'key': c['key'],
    if (c['description'] case final String d when d.isNotEmpty) 'description': d,
    'props': c['props'],
    'variants': [
      for (final v in variants)
        {
          'name': v['name'],
          'props': v['props'],
          if (_image(v, export, dir) case final image?) 'image': image,
        },
    ],
    'instances': instances,
  };
}

/// Grava o PNG da variante (do zip do plugin) em [dir]; null sem imagem (export pelo MCP).
String? _image(Json variant, Export export, Directory dir) {
  final bytes = switch (variant['image']) {
    final String path => export.file(path),
    _ => null,
  };
  if (bytes == null) return null;
  final file = File('${dir.path}/${snakeCase('${variant['name']}')}.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  return file.path;
}
