// shortcut: analyzer 7.7's replacement element model is experimental; migrate after dropping Dart 3.5.
// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/element/element.dart';

/// Ícone do Figma → código Dart `Enum.valor`. Primeiro a exceção pela `mainComponentKey` (`IconTable.byKey`), senão
/// o nome do Figma em camelCase (`arrow-up-right` → `arrowUpRight`), conferido contra o enum. Sem correspondência,
/// o primeiro valor do enum com `TODO(f2d)`: o componente continua na tela e o dev troca o ícone.
String iconCode(Object? value, EnumElement type, {Map<String, String> byKey = const {}}) {
  final constants = type.fields.where((f) => f.isEnumConstant);
  bool exists(String name) => constants.any((c) => c.name == name);
  if (value case {'mainComponentKey': final String key} when byKey[key] != null && exists(byKey[key]!)) {
    return '${type.name}.${byKey[key]}';
  }
  // Set com variant `name` (pode ter outras, como `size`), set de uma variant só, ou um componente por ícone.
  final figmaName = switch (value) {
    String name => name,
    {'variant': {'name': String name}} => name,
    {'variant': Map<String, Object?> variant} when variant.length == 1 => '${variant.values.single}',
    {'componentName': String component} => component.split('/').last.trim(),
    _ => null,
  };
  final camel = figmaName?.replaceAllMapped(RegExp('-(.)'), (x) => x[1]!.toUpperCase());
  if (camel != null && exists(camel)) return '${type.name}.$camel';
  final why = figmaName == null
      ? 'ícone do Figma sem nome legível: $value'
      : 'ícone "$figmaName" do Figma não existe em ${type.name}';
  return '/* TODO(f2d): ${why.replaceAll('*/', '* /')} */ ${type.name}.${constants.first.name}';
}
