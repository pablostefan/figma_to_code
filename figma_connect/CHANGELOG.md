# Changelog

## Não lançado

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
