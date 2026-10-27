# Changelog

## Não lançado

- `@FigmaText` e `FigmaTextProps`: o widget de texto do DS (`AcmeText(t.text(), type: t.style())`). Com ele, cada
  texto do brief vem com o código pronto, no widget e na tipografia do DS, em vez do `Text` do Flutter.
  `@FigmaText.rich` e `FigmaRichTextProps.spans`: o texto com trechos em estilos diferentes (`AcmeRichText`), um
  `TextSpan` por trecho.

- **Removido** (a CLI nunca leu): `tags`, `owner` e `status` (`Status`) do `@FigmaConnect`; `require`,
  `expectedCoverage` e `brief` do `KindPolicy`, com os enums `Field` e `BriefDepth`. O `KindPolicy` fica só com
  `devNotes`. Quem usava: apagar esses argumentos.

- Skill `figma2dart-policy`: o agente `figma-ds-mapper` monta o `lib/figma_policy.dart` (tokens, ícones, ignorados)
  pelo retrato e pelo código do DS, e confere com o `figma2dart doctor`, que agora mostra a cobertura da política
  (`policy`).

- `TokenTable.scopes`: tokens pelo caminho depois da coleção (`Colors/Surface`), em qualquer coleção, para DS em
  que a coleção é a marca (`MarcaA/…`, `MarcaB/…`) e o tema escolhe qual. O caminho mais longo ganha. `TokenSource.names`
  (`{'02': 'two'}`): nome do Figma → membro, para classes que não dá para anotar no doc.

- Agente `figma-ds-mapper` e skill `figma2dart-connect`: componente com base travada exposta (`Button Icon`) vira
  uma anotação só, a partir do zip com o público e as bases. A exposição vem do export (`exposedInstance`), e os
  nomes usados são conferidos contra o export antes do `flutter test`.

- `IconTable.constants(AcmeIcons)`: ícones como constantes estáticas de uma classe (`static const activity =
  AcmeIconData('activity')`), além do enum (`IconTable(values: …)`). `FigmaProps.icon` passa de `T extends Enum` para
  qualquer `T`; quem implementa `FigmaProps` (ex.: um `MapProps` de teste) troca a assinatura para `T icon<T>(…)`.

- `TokenTable` e `TokenSource` no `FigmaPolicy` (`tokens:`): onde cada coleção de variáveis do Figma e os estilos de
  texto estão no código, estáticos (`DsSpacing.md`) ou pelo tema (`via: 'context.acmeSpacing'`).

- `@FigmaLocal(key:, name:, guide:)`: liga um componente do Figma a um widget do app (fora do DS) que já existe;
  anota um `typedef`, em `figma/connect/` do pacote do widget.

- `Coverage.sketch` e o construtor `FigmaConnect.sketch` (`guide` obrigatório): anota um `typedef` para a classe do
  DS, sem função; a LLM monta o widget pela API dele, pelos dados do Figma, pelo norte, docs e exemplos.

## 0.1.0 — 2026-10-25

Primeira versão: os tipos da API descritos em [docs/FIGMA_CONNECT.md](../docs/FIGMA_CONNECT.md).

- `@FigmaConnect` com `key`, `name`, `kind`, `when`, `tags`, `owner`, `status`, `coverage`, `guide`, `figmaNotes`,
  `devNotes`, `docs` e `examples`.
- `@FigmaScreen` e `FigmaScreenProps`, para o que vale em toda tela e só existe no código.
- `FigmaProps`: `text`, `boolean`, `variant`, `icon`, `instance`, `nested`, `slot` e `guided`.
- `FigmaNote` (`ignore`, `derive`, `map`), `DevNote` (`must`, `prefer`), `Doc` (`path`, `link`) e `Example`
  (`code`, `usage`).
- `FigmaPolicy`, `KindPolicy` e `IconTable`, para regras por tipo de componente.

Ajustes da auditoria, antes de qualquer uso:

- `FigmaScreenProps.instance` recebe o mapeamento do componente, não o nome: a busca é pela key.
- Caminhos de `Doc` e `Example` são relativos à raiz do repositório; `Example.usage` ganhou `repo` para apps em
  outros repositórios.
- `FigmaProps.icon` só aceita enum.
- `when` aceita só texto (valor de variant); `fixed` foi removido, porque o corpo da função já fixa o valor.
