import 'icons.dart';
import 'mappings.dart';
import 'resolve.dart' show Json;

/// O que a política cobre do retrato do DS (`figma_library.json`): tokens, estilos de texto e ícones sem código Dart,
/// agrupados para corrigir de uma vez. Só informa; o `doctor` mostra e o agente ajusta a política até zerar.
Json policyCoverage(Json snapshot, Policy policy) {
  final files = ((snapshot['files'] as Map?) ?? const {}).values.cast<Json>();
  final pages = ((snapshot['pages'] as Map?) ?? const {}).values.cast<Json>();
  final tokens = {for (final f in files) ...(f['tokens'] as List).cast<String>()};
  final styles = {for (final f in files) ...(f['textStyles'] as List).cast<String>()};
  final icons = {for (final p in pages) ...((p['icons'] as Map?) ?? const {}).cast<String, String>()};
  return {
    if (tokens.isNotEmpty) 'tokens': _tokens(tokens, policy),
    if (styles.isNotEmpty) 'textStyles': _styles(styles, policy),
    if (icons.isNotEmpty) 'icons': _icons(icons, policy),
  };
}

const _limit = 30;

Json _tokens(Set<String> keys, Policy policy) {
  final missing = <String, Json>{};
  for (final key in keys) {
    final source = policy.tokens?.source(key);
    if (source case (final tokenClass, final name) when tokenClass.code(name) != null) continue;
    final (group, fix, example) = switch (source) {
      (final tokenClass, final name) => (
          tokenClass.prefix,
          'a classe não tem o membro: `names` no TokenSource ou o nome do Figma entre crases no doc do membro',
          '$key → ${tokenClass.member(name)}',
        ),
      null => (
          key.substring(0, key.lastIndexOf('/').clamp(0, key.length)),
          'nenhuma classe: `collections` (pela coleção) ou `scopes` (pelo caminho, em qualquer coleção)',
          key,
        ),
    };
    final entry = missing[group] ??= {'group': group, 'count': 0, 'fix': fix, 'examples': <String>[]};
    entry['count'] = (entry['count'] as int) + 1;
    if ((entry['examples'] as List).length < 3) (entry['examples'] as List).add(example);
  }
  return _report(keys.length, missing.values);
}

Json _styles(Set<String> names, Policy policy) {
  final source = policy.tokens?.textStyles;
  final missing = [
    for (final n in names)
      if (source?.code(n) == null) n
  ];
  return _report(names.length, [
    if (missing.isNotEmpty)
      {
        'group': source?.prefix ?? 'textStyles',
        'count': missing.length,
        'fix': source == null
            ? 'sem `textStyles` no TokenTable'
            : 'a classe não tem o membro: `names` no TokenSource ou o nome do Figma entre crases no doc do membro',
        'examples': [for (final n in missing.take(3)) source == null ? n : '$n → ${source.member(n)}'],
      },
  ]);
}

Json _icons(Map<String, String> icons, Policy policy) {
  final type = policy.icons;
  final missing = [
    for (final MapEntry(:key, value: name) in icons.entries)
      if (type == null ||
          iconCode({
            'mainComponentKey': key,
            'variant': {'name': name}
          }, type, byKey: policy.iconByKey)
              .contains('TODO(f2d)'))
        {'name': name, 'key': key, 'expected': iconCamel(name)},
  ];
  return {
    'total': icons.length,
    'withDart': icons.length - missing.length,
    if (type == null) 'fix': 'sem `icons` no FigmaPolicy: IconTable(values: …) ou IconTable.constants(…)',
    if (type != null && missing.isNotEmpty)
      'fix': 'o nome em camelCase não existe em ${type.name}: `byKey` com a key do ícone, ou o nome certo no DS',
    'missing': missing.take(_limit).toList(),
  };
}

Json _report(int total, Iterable<Json> missing) {
  final groups = missing.toList()..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  return {
    'total': total,
    'withDart': total - groups.fold(0, (sum, g) => sum + (g['count'] as int)),
    'missing': groups.take(_limit).toList(),
  };
}

/// Os ícones de uma página exportada (`figma2dart library`): key → nome do Figma, como o resolvedor lê
/// ([figmaIconName]). Entram os componentes de uma página só de ícones (`Icons`, `🧩 Ícones`; uma página `Button Icon`
/// não) e os sets chamados assim em qualquer página.
Map<String, String> libraryIcons(String page, List<Json> components) {
  // Só a palavra, com emoji, número ou símbolo em volta.
  final onlyIcons = RegExp(r'^[^a-zà-ú]*(icons?|[ií]cones?)[^a-zà-ú]*$', caseSensitive: false);
  final iconPage = onlyIcons.hasMatch(page);
  final out = <String, String>{};
  for (final c in components) {
    if (!iconPage && !onlyIcons.hasMatch(c['name'] as String)) continue;
    final variants = [
      for (final v in ((c['variants'] as List?) ?? const []).cast<Json>())
        if ((v['props'] as Map).isNotEmpty) v,
    ];
    if (variants.isEmpty) {
      out[c['key'] as String] = figmaIconName({'componentName': c['name']})!;
      continue;
    }
    for (final v in variants) {
      // Sem `key` (export anterior ao IR com a key da variant): o id serve para contar, mas não casa com `byKey`.
      if (figmaIconName({'variant': v['props']}) case final name?) out[(v['key'] ?? v['id']) as String] = name;
    }
  }
  return out;
}
