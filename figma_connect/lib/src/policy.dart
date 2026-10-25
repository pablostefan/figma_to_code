import 'annotation.dart';
import 'guidance.dart';

/// Campos que a política de um tipo pode exigir na anotação.
enum Field {
  /// `guide`.
  guide,

  /// Ao menos um `Doc`.
  docs,

  /// Ao menos um `Example.code`.
  exampleCode,
}

/// Quanto do componente entra no brief.
enum BriefDepth {
  /// Nunca aparece.
  none,

  /// Só as lacunas.
  gaps,

  /// Lacunas e exemplos.
  gapsAndExamples,

  /// `guide`, docs e exemplos inteiros.
  full,
}

/// Regras que valem para todos os componentes de um tipo.
class KindPolicy {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 7.
  const KindPolicy({
    this.require = const {},
    this.expectedCoverage,
    this.brief = BriefDepth.gaps,
    this.devNotes = const [],
  });

  /// Campos obrigatórios na anotação.
  final Set<Field> require;

  /// Cobertura esperada; outra dá aviso.
  final Coverage? expectedCoverage;

  /// Profundidade no brief.
  final BriefDepth brief;

  /// Regras comuns ao tipo; entram no brief uma vez.
  final List<DevNote> devNotes;
}

/// Ícones do Figma → valores do enum de ícones do DS.
class IconTable<T extends Enum> {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 7.2.
  const IconTable({required this.values, this.byKey = const {}});

  /// Todos os valores do enum, para a resolução por convenção de nomes.
  final List<T> values;

  /// Exceções pela `mainComponentKey` do ícone.
  final Map<String, T> byKey;
}

/// Tokens do Figma (variáveis e estilos de texto) → código Dart, para o brief já escrever `DsSpacing.md` (ou
/// `context.acmeSpacing.md`) em vez de `Spacing/md`.
class TokenTable {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 7.3.
  const TokenTable({this.collections = const {}, this.textStyles});

  /// Coleção de variáveis do Figma (`Spacing`, `Color`) → onde estão os tokens dela no código.
  final Map<String, TokenSource> collections;

  /// Onde estão os estilos de texto (`body/sm`, `label`).
  final TokenSource? textStyles;
}

/// Uma classe com um membro por token. O membro é achado pelo nome do Figma entre crases no doc dele
/// (`` /// `2xs` = 2 ``) ou, sem isso, pelo nome em camelCase (`text/primary` → `textPrimary`).
class TokenSource {
  /// [via] é a expressão que chega na instância quando o token vem do tema (`context.acmeSpacing`); sem ela, o
  /// membro é estático (`DsSpacing.md`).
  const TokenSource(this.type, {this.via});

  /// A classe com os tokens.
  final Type type;

  /// Expressão até a instância, para tokens do tema (`context.acmeColors`).
  final String? via;
}

/// Política do pacote de mapeamentos: regras por tipo, ícones, tokens e componentes ignorados.
class FigmaPolicy {
  /// Ver `docs/FIGMA_CONNECT.md`, seção 7.
  const FigmaPolicy({this.kinds = const {}, this.icons, this.tokens, this.ignored = const {}});

  /// Regras por tipo.
  final Map<FigmaKind, KindPolicy> kinds;

  /// Tabela de ícones.
  final IconTable? icons;

  /// Tabela de tokens.
  final TokenTable? tokens;

  /// Componentes só do Figma que não seguem o prefixo `_`/`.`: key → motivo.
  final Map<String, String> ignored;
}
