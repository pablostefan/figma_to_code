import 'guidance.dart';

/// Tipo do componente: escolhe as `devNotes` do tipo na política (`FigmaPolicy.kinds`).
enum FigmaKind {
  /// Widget do DS (Button, Input, Badge).
  component,

  /// Bloco composto usado dentro de telas.
  section,

  /// Esqueleto de tela: já traz scaffold e contexto.
  template,

  /// Set de ícones, resolvido pela tabela de ícones.
  icon,
}

/// Quanto do componente a função anotada resolve sem julgamento.
enum Coverage {
  /// Todas as props do Figma que importam são lidas; as outras têm `FigmaNote.ignore`.
  complete,

  /// Parte do componente depende de julgamento; exige norte (`guide` e `f.guided` ou `figmaNotes`).
  partial,

  /// Sem mapeamento campo a campo: a anotação só liga o componente à classe do DS e dá o norte; a LLM monta o
  /// widget pela API dele, pelos dados da instância no Figma, docs e exemplos. Use `FigmaConnect.sketch`.
  sketch,
}

/// Liga um componente do Figma a uma função que monta o widget Dart correspondente.
///
/// A função é um template: a CLI troca cada `f.*` pelos valores da instância no Figma.
/// Referência completa: `docs/FIGMA_CONNECT.md`.
class FigmaConnect {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 3.
  const FigmaConnect({
    required this.key,
    required this.name,
    this.kind = FigmaKind.component,
    this.when = const {},
    this.coverage = Coverage.complete,
    this.guide,
    this.figmaNotes = const {},
    this.devNotes = const [],
    this.docs = const [],
    this.examples = const [],
  });

  /// Liga o componente do Figma à classe do DS sem mapear campos: anota um `typedef` para a classe
  /// (`typedef StatementTemplate = DsStatementTemplate;`), não uma função. A LLM monta o widget com [guide], a API
  /// da classe e os dados da instância no Figma. Ver `docs/FIGMA_CONNECT.md`, seção 5.
  const FigmaConnect.sketch({
    required this.key,
    required this.name,
    required String this.guide,
    this.kind = FigmaKind.component,
    this.when = const {},
    this.figmaNotes = const {},
    this.devNotes = const [],
    this.docs = const [],
    this.examples = const [],
  }) : coverage = Coverage.sketch;

  /// Key do component set (ou do componente sem variants), ou a key exata de uma variant.
  final String key;

  /// Nome no Figma, para humanos (aparece no brief).
  final String name;

  /// Tipo do componente.
  final FigmaKind kind;

  /// Valores de variant que restringem esta função (caso 1 do Figma → N widgets).
  final Map<String, String> when;

  /// Quanto a função resolve sem julgamento.
  final Coverage coverage;

  /// Uma ou duas linhas: o que é o componente e o que falta cobrir.
  final String? guide;

  /// Como ler props do Figma que a função não lê, pelo nome da prop.
  final Map<String, FigmaNote> figmaNotes;

  /// Regras de uso no código, válidas em qualquer tela.
  final List<DevNote> devNotes;

  /// Onde está a documentação.
  final List<Doc> docs;

  /// Exemplos de implementação.
  final List<Example> examples;
}

/// Componente do app (fora do DS) que já existe no código. Anota um `typedef` para a classe do widget, num arquivo
/// `figma/connect/*.figma.dart` do pacote que tem o widget (fora de `lib/`):
///
/// ```dart
/// @FigmaLocal(key: '2672912…', name: 'ContactItem')
/// typedef ContactItemFigma = ContactItem;
/// ```
///
/// A instância desse componente vira tarefa de montagem (`f2d:local`): a LLM usa o widget com a API dele e os dados
/// do Figma, como no `FigmaConnect.sketch`, em vez de construir um novo. `figma2dart link` escreve este arquivo.
class FigmaLocal {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 5.1.
  const FigmaLocal({required this.key, required this.name, this.guide});

  /// Key do componente (ou do component set) no Figma.
  final String key;

  /// Nome do componente no Figma (só para leitura).
  final String name;

  /// Norte para montar, quando a API do widget não basta.
  final String? guide;
}

/// Mapeamento de tela: o que vale em toda tela e só existe no código (contexto, scaffold).
class FigmaScreen {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 8.
  const FigmaScreen();
}
