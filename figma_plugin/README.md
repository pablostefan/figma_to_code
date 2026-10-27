# figma2dart Export (plugin + extrator MCP)

Exporta componentes, telas e fluxos do Figma no formato **IR v1** consumido pelo `figma2dart`.
O mesmo extrator roda em dois lugares e gera o mesmo JSON:

- **Plugin do Figma:** para designers, sem Dev Mode. Gera um `.zip` com `export.json` + imagens.
- **MCP (`use_figma`):** para agentes e CI. Devolve o JSON (paginado quando passa de 48 KB).

O formato (IR), os tipos de export e a profundidade de cada nó: [docs/ARQUITETURA.md §2](../docs/ARQUITETURA.md#2-o-ir-o-contrato-com-o-figma).

## Build

```bash
npm install
npm run build     # dist/code.js, dist/ui.html, dist/mcp-extractor.js
npm run check     # typecheck + schema + testes + build + valida os exemplos
```

| Script | O que faz |
|---|---|
| `build` / `watch` | gera os três bundles |
| `typecheck` | `tsc --noEmit` |
| `schema` | regenera `schema/ir.v1.schema.json` a partir de `src/extractor/ir.ts` |
| `test` | testa seleção, overrides, dependências locais, paginação e compatibilidade do schema |
| `validate -- <arquivos>` | valida exports contra o schema |

## Usar no Figma

1. `npm install && npm run build`, dentro de `figma_plugin/`. A pasta `dist/` não é versionada: sem o build, o
   Figma mostra "Ocorreu um erro ao carregar o ambiente do plugin" e, no console, `ENOENT … dist/code.js`.
   Depois de um `git pull`, rode o build de novo.
2. No Figma desktop: **Plugins → Development → Import plugin from manifest…** e escolha `manifest.json`.
   Roda no modo Design e no Dev Mode (no painel Inspect); o plugin só lê o arquivo.
3. Selecione o que exportar e rode **figma2dart Export**:

| Seleção | Tipo inferido |
|---|---|
| Component set, componente ou variant | Componente |
| 1 frame | Tela |
| 2+ frames ou uma section | Fluxo (inclui a navegação do protótipo) |
| Nada | Biblioteca (componentes da página atual + todos os tokens) |

4. Dá para trocar o tipo, escrever notas para o dev, **Verificar** (mostra o lint), **Copiar JSON** ou
   **Exportar .zip**. Clicar num aviso do lint leva até a camada.

Frames nomeados `Tela / estado` (ex.: `Dashboard / vazio`) viram estados da mesma tela.

## Usar pelo MCP

O agente lê `dist/mcp-extractor.js` e envia como `code` do `use_figma`, com uma linha de chamada no fim:

```js
// <conteúdo de dist/mcp-extractor.js>
return await F2D.run({ nodeIds: ['7:197'] });
```

Opções de `F2D.run`:

| Opção | Uso |
|---|---|
| `nodeIds` | nós a exportar (vazio = biblioteca) |
| `pageId` | página da exportação de biblioteca |
| `kind` | força `component`, `screen`, `flow` ou `library` |
| `notes` | vai para `intent.notes` |
| `page`, `exportedAt` | paginação (abaixo) |

**Paginação.** Se o IR passar do limite de retorno do `use_figma` (48 000 bytes), a resposta vem como
`{ page: 0, pages: N, exportedAt, data }`. Chame de novo com `page: 1 … N-1` **e o mesmo `exportedAt`**,
concatene os `data` em ordem e faça `JSON.parse`:

```js
return await F2D.run({ nodeIds: [...], exportedAt: '2026-10-25T00:00:00.000Z', page: 1 });
```

Pelo MCP não há imagens no IR: use a ferramenta `get_screenshot` com os ids de `screens[].states[].id` ou
`components[].variants[].id`.

## Estrutura

```
src/extractor/   extrator compartilhado (Plugin API → IR). Sem dependências.
  ir.ts          tipos do IR v1 — fonte do schema
  context.ts     tokens, text styles, componentRefs, lint, imagens
  serialize.ts   nós: layout, estilo, texto, instâncias (rasas), overrides
  extract.ts     inferência do kind, componentes, telas/estados, fluxo
src/plugin/      main do plugin (sandbox do Figma, sem DOM) e mensagens
src/ui/          UI do plugin (iframe com DOM; zip com fflate), tsconfig próprio
src/mcp/         entrada do use_figma + paginação
schema/          ir.v1.schema.json (gerado)
examples/        exports reais do POC, usados como fixtures
scripts/         build e validação
tests/           invariantes do extrator e do contrato
```

## Exemplos

Gerados via MCP a partir dos arquivos do POC:

- `examples/component-transaction-item.ir.json` — `kind: component` (TransactionItem, 2 variants). Gerado antes de
  `overrides[].values` existir: os overrides dele não trazem valores.
- `examples/flow-transferencia.ir.json` — `kind: flow` (5 telas, 4 componentes locais, 7 navegações, lint).

O IR só ganha campos opcionais entre versões, então exports antigos continuam válidos.

## DS maiores

O extrator não depende de nenhum DS: lê só a Plugin API. Cobre modos de variável (temas e marcas), estilos de cor,
nomes repetidos entre bibliotecas, alias para variável de outra biblioteca, texto e camadas alterados sem prop,
templates dentro do arquivo do DS, sections aninhadas e grid.

Continuam sendo convenção (afetam só agrupamento e lint, sem perder dados): estados por `Tela / estado` no nome do
frame, biblioteca por página, e variável de tipografia direto no texto sem text style (sai como fonte solta, com o
lint `text-without-style`).

## Limitações conhecidas

- **`fileName` no MCP:** o runtime do `use_figma` devolve `Document` como `figma.root.name`. Use `fileKey`.
- **SVG:** a exportação de SVG de componentes só-vetor (ícones) depende do ambiente; pelo MCP pode não vir.
- **Biblioteca:** considera os componentes da página atual (ou de `pageId`), não do arquivo inteiro.
- **Exports grandes pelo MCP:** cada página reexecuta a extração. Para centenas de componentes, divida em lotes de
  `nodeIds` em vez de paginar um IR só.
- **`fileKey` no plugin:** só vem quando o plugin é publicado como privado da organização. Importado como plugin de
  desenvolvimento, o export traz `fileName`, mas não `fileKey`.
