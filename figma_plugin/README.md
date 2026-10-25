# figma2dart Export (plugin + extrator MCP)

Exporta componentes, telas e fluxos do Figma no formato **IR v1** consumido pelo `figma2dart`.
O mesmo extrator roda em dois lugares e gera o mesmo JSON:

- **Plugin do Figma:** para designers, sem Dev Mode. Gera um `.zip` com `export.json` + imagens.
- **MCP (`use_figma`):** para agentes e CI. Devolve o JSON (paginado quando passa de 48 KB).

Arquitetura e decisões: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md), seções 4 a 6.
Histórico de mudanças: [docs/CHANGELOG.md](../docs/CHANGELOG.md).

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

1. `npm run build`.
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

Os dois saíram do extrator 0.1 (IR 1.0.0). IR 1.1 e 1.2 só acrescentam campos opcionais, então continuam válidos.

## DS maiores

O extrator não depende do DS do POC: cobre modos de variável, estilos de cor, nomes repetidos entre bibliotecas,
texto e camadas alterados sem prop, templates dentro do arquivo do DS, sections aninhadas e grid. O que ainda é
convenção está em [ARCHITECTURE.md, seção 5.8](../docs/ARCHITECTURE.md).

## Limitações conhecidas

- **`fileName` no MCP:** o runtime do `use_figma` devolve `Document` como `figma.root.name`. Use `fileKey`.
- **SVG:** a exportação de SVG de componentes só-vetor (ícones) depende do ambiente; pelo MCP pode não vir.
- **Biblioteca:** considera os componentes da página atual (ou de `pageId`), não do arquivo inteiro.
- **Exports grandes pelo MCP:** cada página reexecuta a extração. Para centenas de componentes, divida em lotes de
  `nodeIds` em vez de paginar um IR só.
- **`fileKey` no plugin:** só vem quando o plugin é publicado como privado da organização. Importado como plugin de
  desenvolvimento, o export traz `fileName`, mas não `fileKey`.
- **Teste:** plugin rodado no Figma desktop (tela e fluxo do POC). O IR saiu igual ao do MCP, exceto `source.via`,
  `fileKey` e as imagens.
