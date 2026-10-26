# 10 · Export para anotação no plugin

## Problema

Para escrever uma anotação, o agente precisa de tudo o que o painel **"Explorar comportamento do componente"** do
Figma mostra, com a key e os nomes exatos. Hoje nenhuma fonte dá isso inteiro:

| Fonte | Falta |
|---|---|
| Export do plugin (IR, modo Componente) | quais instâncias internas são **expostas**; nome do ícone padrão (o swap vem como id do nó); opções permitidas do swap (`preferredValues`); qual base aparece em cada variante do público (`Button Icon` Size=Large → `.Icon Button / Large`); que camada cada prop controla. O IR foi feito para telas, não para anotar |
| MCP local do Figma | só lê; não dá a key; converte os nomes das props (`🔔 Notification` → `notification`) |
| Retrato (`figma_library.json`) | só key → nome |

## Proposta

Um export **separado** no plugin, só para anotar, sem mexer no export de hoje (IR, CLI e telas continuam iguais).

**No plugin:**

- **UI:** uma aba **Anotar**, ao lado da de hoje, com a mesma seleção. Aceita component sets, componentes ou uma
  section com componentes. O botão é **Exportar para anotação**.
- **Código:** módulo próprio, `src/connect/`, que reaproveita só utilitários do extrator (`propName`, `ownerOf`,
  exportação de PNG). O `src/extractor/` não muda.
- **Saída:** `figma2dart-connect-<nome>.zip` com:
  - `connect.json`, num esquema próprio e versionado (`connectVersion`);
  - os PNGs.
- **Tamanho:** sem árvore de nós. É o "painel do componente" em JSON, bem menor que o IR.

## O que o `connect.json` traz

Para cada componente selecionado e para cada base exposta dentro dele (deduplicada pela key):

```jsonc
{
  "connectVersion": "1.0",
  "source": { "fileKey": "…", "fileName": "Acme", "page": "Buttons" },
  "components": [
    {
      "key": "e8186571…", "id": "74488:100", "name": "Button Icon", "published": true,
      "description": "botão com ícone, …",
      "props": {
        "👉 Size": { "type": "VARIANT", "default": "Large", "options": ["Medium", "Small", "Large"] }
      },
      "variants": [
        {
          "props": { "👉 Size": "Large" }, "key": "…", "image": "images/button_icon/size_large.png",
          "exposed": [
            { "path": "✏️ Icon Button", "key": "4d37082c…", "name": ".Icon Button / Large",
              "values": { "✏️ Type": "Primary", "🔒 Disabled": "False", "🔄 Icon": "Icon name=image" } }
          ]
        }
      ]
    },
    {
      "key": "4d37082c…", "name": ".Icon Button / Large", "published": false, "base": true,
      "usedBy": [{ "key": "e8186571…", "name": "Button Icon", "path": "✏️ Icon Button", "when": { "👉 Size": "Large" } }],
      "props": {
        "🔄 Icon":   { "type": "INSTANCE_SWAP", "default": "Icon name=image",
                       "preferred": ["Icon name=image", "Icon name=bell", "…"] },
        "🔔 Notification": { "type": "BOOLEAN", "default": false, "controls": ["badge"] },
        "✏️ Type":   { "type": "VARIANT", "default": "Primary", "options": ["Primary", "Secondary", "Tertiary"] },
        "🔒 Disabled": { "type": "VARIANT", "default": "False", "options": ["True", "False"] }
      },
      "variants": [ { "props": { "✏️ Type": "Primary", "🔒 Disabled": "False", … }, "key": "…", "image": "…" } ]
    }
  ]
}
```

## Casos que o export precisa cobrir

| # | Caso | Exemplo | Campo no export |
|---|---|---|---|
| 1 | Component set simples | Badge (`tone`) | `props`, `variants` |
| 2 | Componente sem variantes | ícone avulso | `variants` com um item, `props` vazio |
| 3 | Público com base travada exposta | `Button Icon` → `.Icon Button / Large` | `variants[].exposed` + a base com `base`, `usedBy` |
| 4 | Exposta dentro de exposta (vários níveis) | `Input` → `trailingAction` → `Icon` | `exposed[].exposed`, recursivo |
| 5 | Swap de ícone | `🔄 Icon` | `default` e `preferred` pelo nome do ícone, não pelo id |
| 6 | Swap de outro componente (slot) | conteúdo trocável | `preferred` com o nome de cada componente |
| 7 | Boolean que mostra ou esconde camada | `🔔 Notification` | `controls`: as camadas ligadas (`componentPropertyReferences.visible`) |
| 8 | Texto ligado a camada | `label` | `controls`: a camada do texto (`characters`) |
| 9 | Variante que troca a estrutura | Avatar `type=icon` × `initials` | um PNG por variante, e `controls` diferente por variante (vira `when` na anotação) |
| 10 | Base usada solta, fora do público | `.Icon Button / Exclusive` | `published: false` sem `usedBy` |
| 11 | Componente de outra biblioteca dentro | ícone de outra lib | `exposed[].remote: true`, com a key |
| 12 | Template (conteúdo são camadas) | Extrato | `slots`: camadas de primeiro nível sem prop, para virar `sketch` |
| 13 | Nome com emoji ou símbolo | `✏️ Type` | o nome exato, sempre; nunca normalizado |
| 14 | Muitas variantes | 3 × 3 × 2 × 2 = 36 | opção na UI: PNG de todas as variantes ou só das diferentes por prop |

## O que muda no resto

- **Agente e skill de anotar:** leem o `connect.json` em vez do `export.json`:
  - as bases (`base: true`) entram no mesmo lote do público;
  - a proposta A do [plano 09](09-bases-travadas.md) sai direto do `usedBy` e do `exposed`.
- **Inventário:** continua pelo retrato (`figma2dart library`).
- **CLI:** nada. O agente lê o JSON; o `resolve` continua lendo o IR.
- **Plano 09:** a correção do prefixo `.` (base com anotação entra na tela) continua necessária.

## Tarefas

- [ ] `src/connect/`: `connect.json` a partir da seleção; bases deduplicadas; `usedBy`; `preferred` e `default` do
  swap pelo nome; `controls` pelas `componentPropertyReferences`; `exposed` recursivo; `slots`.
- [ ] Esquema `schema/connect.v1.schema.json` e testes em `tests/` com nós falsos (casos 1–13).
- [ ] UI: aba **Anotar**, opção de imagens (todas / uma por prop), **Exportar para anotação**.
- [ ] Skill `figma2dart-connect` e agente `figma-ds-mapper` lendo o `connect.json`.
- [ ] Docs: README do plugin, COMO_FUNCIONA (A3), FIGMA_CONNECT (de onde vem cada dado da anotação).

## Verificação

- `npm run check` no plugin (tipos, esquema, testes, build).
- No arquivo do Carteira DS: exportar Input, Avatar e TransactionItem para anotação. O agente, numa cópia sem as
  anotações, refaz as três, e a gente compara com as originais.
- No Acme: exportar a família `Button Icon` (público e as quatro bases) e conferir os casos 3, 5, 7 e 10.

## Decisões em aberto

1. Aba **Anotar** ou um botão a mais na tela de hoje? (Recomendado: aba, porque a seleção e as opções são outras.)
2. PNG de todas as variantes ou só das que mudam uma prop por vez? (Recomendado: por padrão, uma por opção de prop
   a partir da padrão; "todas" como opção.)
3. Incluir o `Code Connect` existente? A Plugin API não lê o Code Connect; só o MCP (`get_code_connect_map`). Fica
   como passo opcional do agente.
