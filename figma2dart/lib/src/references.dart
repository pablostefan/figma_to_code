import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'mappings.dart';

/// Docs e exemplos de um componente, lidos do disco para entrar no brief: conteúdo, não link (FIGMA_CONNECT §6).
class References {
  References(this.root);

  /// Pasta do pacote de mapeamentos. Caminhos de `Doc` e `Example` são relativos à raiz do repositório, então a busca
  /// sobe a partir daqui.
  final String root;

  /// Exemplo maior que isso entra só como caminho e dica (§6.2).
  static const maxExampleLines = 60;

  /// Doc inteiro de componente `partial`/`sketch` acima disso é cortado.
  static const maxDocLines = 150;

  /// Markdown com os docs e exemplos de [m]. Componente `complete` leva só `Geral`, as seções das partes decididas
  /// nesta tela ([parts]) e `Erros comuns`; `partial`/`sketch` leva o doc inteiro.
  String render(Mapping m, Set<String> parts) {
    final whole = m.coverage != 'complete';
    final out = StringBuffer();
    final docs = m.docs.isNotEmpty ? m.docs : _conventional(m);
    for (final d in docs) {
      _doc(out, d, whole: whole, parts: parts);
    }
    // No máximo 1 `code` e 1 `usage` (§6.2).
    for (final kind in ['code', 'usage']) {
      if (m.examples.where((e) => e.kind == kind).firstOrNull case final e?) _example(out, e);
    }
    return out.toString().trim();
  }

  /// Sem `docs` na anotação: `docs/<arquivo>.md` do pacote, com o nome do `*.figma.dart`.
  List<DocRef> _conventional(Mapping m) {
    final stem = m.file.split('/').last.replaceFirst('.figma.dart', '');
    final path = '${root.split('/').last}/docs/$stem.md'; // relativo à raiz do repositório, como os explícitos
    return [
      if (File('$root/docs/$stem.md').existsSync()) (path: path, url: null, source: null, section: null, hint: null),
    ];
  }

  void _doc(StringBuffer out, DocRef d, {required bool whole, required Set<String> parts}) {
    final local = d.path ?? d.source;
    final label = [d.path ?? d.url, if (d.section case final s?) ' § $s', if (d.hint case final h?) ' — $h'].join();
    final file = local == null ? null : _find(local);
    if (file == null) {
      out.writeln(
        local == null
            ? '- Doc: $label (online, sem `source`: abra se precisar)'
            : '- Doc: $label **(não encontrado: `$local`)**',
      );
      return;
    }
    final sections = _sections(file.readAsStringSync());
    final wanted = d.section != null
        ? {d.section!}
        : whole
        ? null
        : {'geral', ...parts, 'erros comuns'};
    final picked = [
      for (final MapEntry(key: title, value: body) in sections.entries)
        if (wanted == null || wanted.any((w) => w.toLowerCase() == title.toLowerCase())) body,
    ];
    if (d.section != null && picked.isEmpty) {
      out.writeln('- Doc: $label **(seção "${d.section}" não existe no arquivo)**');
      return;
    }
    if (picked.isEmpty) return;
    var lines = picked.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim().split('\n');
    final cut = lines.length > maxDocLines;
    if (cut) lines = lines.take(maxDocLines).toList();
    out
      ..writeln()
      ..writeln('Doc: $label')
      ..writeln()
      ..writeln(lines.map((l) => l.startsWith('#') ? '##$l' : l).join('\n')) // abaixo do `###` do componente
      ..writeln(cut ? '\n(cortado em $maxDocLines linhas: o resto está em `$local`)' : '');
  }

  void _example(StringBuffer out, ExampleRef e) {
    final where = '${e.repo == null ? '' : '${e.repo}:'}`${e.path}` · `${e.symbol}`';
    final title = [
      e.kind == 'code' ? 'Exemplo (modelo para seguir)' : 'Uso real (contexto: não copie a lógica de negócio)',
      if (e.hint case final h?) ' — $h',
    ].join();
    final file = _find(e.path);
    final code = file == null ? null : _symbol(file.readAsStringSync(), e.symbol);
    final lines = code?.split('\n').length ?? 0;
    if (code == null || lines > maxExampleLines) {
      final why = file == null
          ? 'arquivo não encontrado${e.repo == null ? '' : ' (repositório ${e.repo})'}'
          : code == null
          ? 'símbolo não encontrado'
          : '$lines linhas: abra o arquivo';
      out.writeln('- $title: $where ($why)');
      return;
    }
    out
      ..writeln()
      ..writeln('$title: $where')
      ..writeln()
      ..writeln('```dart')
      ..writeln(code)
      ..writeln('```');
  }

  /// Seções `## Título` do markdown, pelo título; o que vem antes da primeira fica de fora (é o `# Nome`). Sem
  /// nenhuma seção, o texto todo vira `Geral`.
  static Map<String, String> _sections(String markdown) {
    final out = <String, String>{};
    String? title;
    final body = StringBuffer();
    void flush() {
      if (title != null) out[title] = body.toString();
      body.clear();
    }

    for (final line in markdown.split('\n')) {
      if (line.startsWith('## ')) {
        flush();
        title = line.substring(3).replaceAll('`', '').trim(); // `## \`onPressed\`` casa com a parte onPressed
      }
      if (title != null) body.writeln(line);
    }
    flush();
    // Doc sem nenhum `##`: o texto todo (menos o `# Nome`) é a seção Geral, para não sumir do brief.
    if (out.isEmpty) out['Geral'] = markdown.split('\n').where((l) => !l.startsWith('# ')).join('\n');
    return out;
  }

  /// Código do símbolo (`Classe`, `funcao` ou `Classe.metodo`), com o comentário de doc.
  static String? _symbol(String source, String symbol) {
    final unit = parseString(content: source, throwIfDiagnostics: false).unit;
    final [name, ...member] = symbol.split('.');
    for (final d in unit.declarations) {
      if (d is FunctionDeclaration && member.isEmpty && d.name.lexeme == name) {
        return source.substring(d.offset, d.end);
      }
      if (d is ClassDeclaration && d.name.lexeme == name) {
        if (member.isEmpty) return source.substring(d.offset, d.end);
        final m = d.members.whereType<MethodDeclaration>().where((m) => m.name.lexeme == member.single);
        if (m.firstOrNull case final m?) return '  ${source.substring(m.offset, m.end)}';
      }
    }
    return null;
  }

  /// Arquivo relativo à raiz do repositório: tenta a partir do pacote e sobe até achar.
  File? _find(String path) {
    if (path.startsWith('/')) return File(path).existsSync() ? File(path) : null;
    for (var dir = Directory(root); ; dir = dir.parent) {
      final file = File('${dir.path}/$path');
      if (file.existsSync()) return file;
      if (dir.parent.path == dir.path) return null;
    }
  }
}
