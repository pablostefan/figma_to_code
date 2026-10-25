/// Nomes do Figma → nomes Dart. Nomes em português são comuns: acento vira a letra sem acento, não some.
library;

/// Pasta e arquivo: `Cartão de Crédito` → `cartao_de_credito`.
String snakeCase(String name) => _safe(_words(name).map((w) => w.toLowerCase()).join('_'), 'c_', 'component');

/// Tela → pasta da tarefa e arquivo: sem a numeração do fluxo (`04 · Confirmar` → `confirmar`).
String screenSlug(String name) => snakeCase(name.replaceFirst(RegExp(r'^\s*\d+\s*[·.\-]\s*'), ''));

/// Classe: `contact item` → `ContactItem`.
String pascalCase(String name) => _safe(_words(name).map(_capitalize).join(), 'C', 'Component');

/// Campo, parâmetro ou valor de enum: `Mostrar ícone` → `mostrarIcone`; `default` → `defaultValue`; `2xl` → `x2xl`.
String identifier(String name) {
  final words = _words(name);
  final camel = words.isEmpty ? '' : words.first.toLowerCase() + words.skip(1).map(_capitalize).join();
  final id = _safe(camel, 'x', 'value');
  return _reserved.contains(id) ? '${id}Value' : id;
}

String _capitalize(String w) => w[0].toUpperCase() + w.substring(1);

/// Vazio vira [empty]; começando com número ganha [prefix] (identificador Dart não começa com dígito).
String _safe(String s, String prefix, String empty) => s.isEmpty
    ? empty
    : RegExp('^[0-9]').hasMatch(s)
    ? '$prefix$s'
    : s;

List<String> _words(String name) => _plain(name)
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
    .split(RegExp('[^A-Za-z0-9]+'))
    .where((w) => w.isNotEmpty)
    .toList();

String _plain(String s) => s.split('').map((c) => _accents[c] ?? c).join();

const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', //
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ç': 'c', 'ñ': 'n', //
  'Á': 'A', 'À': 'A', 'Â': 'A', 'Ã': 'A', 'Ä': 'A', 'É': 'E', 'È': 'E', 'Ê': 'E', 'Ë': 'E', //
  'Í': 'I', 'Ì': 'I', 'Î': 'I', 'Ï': 'I', 'Ó': 'O', 'Ò': 'O', 'Ô': 'O', 'Õ': 'O', 'Ö': 'O', //
  'Ú': 'U', 'Ù': 'U', 'Û': 'U', 'Ü': 'U', 'Ç': 'C', 'Ñ': 'N',
};

/// Palavras reservadas do Dart: não servem de nome de campo nem de valor de enum.
const _reserved = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'do', 'else', 'enum', 'extends', //
  'false', 'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super', 'switch', //
  'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
};
