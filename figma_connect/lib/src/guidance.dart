/// Como ler uma prop do Figma que não vira parâmetro no código.
sealed class FigmaNote {
  const FigmaNote._();

  /// Prop só visual, sem efeito no código: não vira lacuna.
  const factory FigmaNote.ignore(String reason) = IgnoreNote;

  /// O efeito existe, mas vem de outra coisa: vira norte no brief.
  const factory FigmaNote.derive(String guide) = DeriveNote;

  /// Correspondência conhecida que ainda não está no corpo da função.
  const factory FigmaNote.map(Map<String, Object?> values, {String? hint}) = MapNote;
}

/// Ver [FigmaNote.ignore].
final class IgnoreNote extends FigmaNote {
  /// Ver [FigmaNote.ignore].
  const IgnoreNote(this.reason) : super._();

  /// Por que a prop não importa.
  final String reason;
}

/// Ver [FigmaNote.derive].
final class DeriveNote extends FigmaNote {
  /// Ver [FigmaNote.derive].
  const DeriveNote(this.guide) : super._();

  /// De onde vem o efeito.
  final String guide;
}

/// Ver [FigmaNote.map].
final class MapNote extends FigmaNote {
  /// Ver [FigmaNote.map].
  const MapNote(this.values, {this.hint}) : super._();

  /// Valor do Figma → valor no código.
  final Map<String, Object?> values;

  /// Uma linha de contexto.
  final String? hint;
}

/// Regra de uso do componente no código.
sealed class DevNote {
  const DevNote._();

  /// Obrigatório. Se for verificável, [lint] aponta a regra que a cobra.
  const factory DevNote.must(String rule, {String? lint}) = MustNote;

  /// Recomendação: a LLM pode fugir, marcando `f2d:inferred` com o motivo.
  const factory DevNote.prefer(String rule) = PreferNote;
}

/// Ver [DevNote.must].
final class MustNote extends DevNote {
  /// Ver [DevNote.must].
  const MustNote(this.rule, {this.lint}) : super._();

  /// A regra, em uma frase.
  final String rule;

  /// Id do lint que cobra a regra.
  final String? lint;
}

/// Ver [DevNote.prefer].
final class PreferNote extends DevNote {
  /// Ver [DevNote.prefer].
  const PreferNote(this.rule) : super._();

  /// A regra, em uma frase.
  final String rule;
}

/// Onde está a documentação de um componente ou de uma parte dele.
sealed class Doc {
  const Doc._();

  /// Arquivo no repositório do DS, com caminho relativo à raiz dele.
  const factory Doc.path(String path, {String? section, String? hint}) = PathDoc;

  /// Doc online; [source] é o arquivo de origem no repositório, para ler sem rede.
  const factory Doc.link(String url, {String? section, String? hint, String? source}) = LinkDoc;

  /// Trecho que interessa, com o mesmo nome da parte (`filters`).
  String? get section;

  /// Uma linha: o que tem no doc e quando ele importa.
  String? get hint;
}

/// Ver [Doc.path].
final class PathDoc extends Doc {
  /// Ver [Doc.path].
  const PathDoc(this.path, {this.section, this.hint}) : super._();

  /// Caminho relativo à raiz do repositório do DS.
  final String path;

  @override
  final String? section;

  @override
  final String? hint;
}

/// Ver [Doc.link].
final class LinkDoc extends Doc {
  /// Ver [Doc.link].
  const LinkDoc(this.url, {this.section, this.hint, this.source}) : super._();

  /// URL do doc.
  final String url;

  /// Arquivo de origem, relativo à raiz do repositório do DS.
  final String? source;

  @override
  final String? section;

  @override
  final String? hint;
}

/// Exemplo de implementação, referenciado por símbolo (classe, função ou `Classe.metodo`).
sealed class Example {
  const Example._();

  /// Exemplo escrito para isso, no pacote de exemplos: modelo para seguir.
  const factory Example.code(String path, {required String symbol, String? hint}) = CodeExample;

  /// Uso real num app: referência de contexto, sem copiar a lógica de negócio. [repo] identifica o repositório do
  /// app quando não é o do DS.
  const factory Example.usage(String path, {required String symbol, String? repo, String? hint}) = UsageExample;

  /// Arquivo Dart, relativo à raiz do repositório (o do DS, ou [UsageExample.repo]).
  String get path;

  /// Classe, função ou método dentro de [path].
  String get symbol;

  /// Uma linha: que caso o exemplo mostra.
  String? get hint;
}

/// Ver [Example.code].
final class CodeExample extends Example {
  /// Ver [Example.code].
  const CodeExample(this.path, {required this.symbol, this.hint}) : super._();

  @override
  final String path;

  @override
  final String symbol;

  @override
  final String? hint;
}

/// Ver [Example.usage].
final class UsageExample extends Example {
  /// Ver [Example.usage].
  const UsageExample(this.path, {required this.symbol, this.repo, this.hint}) : super._();

  @override
  final String path;

  /// Repositório do app (ex.: `extrato-app`); `null` = repositório do DS.
  final String? repo;

  @override
  final String symbol;

  @override
  final String? hint;
}
