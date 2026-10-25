# figma2dart — Arquitetura

Ferramenta para transformar designs do Figma em código Flutter que **usa o Design System existente**
(widgets e tokens), em vez de redesenhar telas com `Container` e valores fixos.

Validada primeiro neste POC (Carteira DS, 10 componentes, 2 templates, 1 fluxo de 5 telas) e pensada para
escalar para um DS com 300+ componentes e 12 templates, onde o código nem sempre espelha o Figma 1:1.

**Objetivo final:** a tela inteira implementada, **incluindo os componentes que não estão no DS** e precisam ser
construídos. A ferramenta deve entregar tudo o que é necessário para construí-los corretamente: variants e estados,
props, tokens já traduzidos, componentes do DS usados dentro, assets, onde criar, regras e exemplo.

**Escopo atual:** só a parte do DS é transcrita. O que está fora do DS vira **placeholder** (seção 10.5) e o dev
substitui depois. A construção de componentes fora do DS é uma **feature futura importante**, com o usuário
escolhendo se cria ou não cada componente. Nenhuma decisão pode impedir ou dificultar essa feature: as restrições
estão na seção 13.

---

## 1. Restrições que moldaram as decisões

| Restrição | Consequência |
|---|---|
| Code Connect é escrito em TypeScript e só aparece para quem tem **Dev Mode** | Não usamos Code Connect. O mapeamento Figma → código fica em **Dart**, no repositório. |
| Poucas pessoas na empresa têm Dev Mode | Nada no fluxo depende de Dev Mode. Quem consome lê arquivos do repositório. |
| A REST API de **Variables** só existe no Enterprise | Nomes de tokens vêm da **Plugin API** (plugin ou `use_figma`), que funciona em qualquer plano. |
| A REST API tem cota por tipo de seat (View/Collab muito baixa) | Ninguém além do exportador ou da CI fala com o Figma. O resto do time usa o snapshot commitado. |
| Os componentes do DS **não devem ser alterados** para atender a ferramenta | O mapeamento vive em arquivos `.figma.dart` **separados**, num pacote à parte. |
| O código nem sempre é igual ao Figma (nomes, props, estrutura) | As divergências são declaradas explicitamente no mapeamento e reportadas como drift. |
| Templates e componentes compostos não seguem os atributos do Figma | Nem tudo é determinístico. A anotação cobre o que dá e deixa um **norte** para o resto, que a LLM implementa (seções 7.6 e 10). |
| Componentes essenciais só existem no código (`AcmeContext`, `AcmeScaffold`) | Entram pelo gerador ou pelas regras e notas das anotações; nunca dependem do Figma (seção 10.2). |
| Os times usam Copilot e opencode; a LLM padrão da empresa é o Luna 5.6 | Entrega por CLI + MCP + skill, que os dois entendem. Tarefas pequenas, com critério de pronto verificável (seção 10). |

---

## 2. Visão geral

```
                    ┌──────────────────────── Figma ────────────────────────┐
                    │                                                        │
   Designer ── Plugin (extrator) ──┐                     MCP ──┬── use_figma + extrator
                                   │                           └── get_design_context / get_metadata / get_variable_defs
                                   ▼                                   │
                            IR v1 (JSON) ◄──── importer MCP ───────────┘
                                   │
                                   ▼
                     figma_specs/  (snapshot commitado)
                                   │
          ┌────────────────────────┼─────────────────────────┐
          ▼                        ▼                         ▼
   figma2dart generate      figma2dart drift          golden tests
   (tela → Dart)            (Figma × mapeamento)       (widget × PNG do Figma)
          ▲         │ rascunho que compila + marcadores (f2d:guided / f2d:gap)
          │         ▼
          │   figma2dart resolve ──► LLM (agente + skills no Copilot) ──► figma2dart check
          │
   carteira_ds_figma/  *.figma.dart (mapeamento + norte) · docs/ · rules/
```

Princípios centrais:

- **A ferramenta só conhece o IR.** Não importa se ele veio do plugin, do MCP com o extrator ou do MCP nativo.
- **O que é determinístico, a LLM recebe pronto.** O que não é, ela implementa seguindo o norte das anotações e
  os docs, e marca o que decidiu. Regra que pode virar código vira código (gerador ou lint).

---

## 3. Estrutura dos repositórios

```
figma_to_code/                     ← ferramenta (este repositório)
  docs/ARCHITECTURE.md
  docs/FIGMA_CONNECT.md            ← referência completa da anotação @FigmaConnect
  figma_plugin/
    src/extractor/                 ← TS, sem dependências. Plugin API → IR v1 (compartilhado)
    src/plugin/                    ← main do plugin (sandbox do Figma, sem DOM)
    src/ui/                        ← UI do plugin (iframe com DOM), tsconfig próprio
    src/mcp/                       ← entrada do mesmo extrator para o use_figma
    schema/ir.v1.schema.json       ← contrato (gerado a partir dos tipos TS)
  figma_connect/                   ← pacote Flutter: @FigmaConnect, FigmaProps, política (API dos mapeamentos)
  figma2dart/                      ← CLI Dart: setup, doctor, packages, screens, resolve, check, init
    tool/figma2dart                ← script que roda a CLI; o `setup` copia para o PATH
    tool/figma2dart.rake           ← `rake figma2dart:setup` para o Rakefile de um monorepo
    agent/                         ← agente figma-to-flutter + subagente + skills (referência; o `init` instala
                                     num app só)

design_system/                     ← repositório do DS
  carteira_design_system/          ← widgets + tokens (INTOCADO pela ferramenta)
  carteira_ds_figma/               ← mapeamentos *.figma.dart (depende do DS e do figma_connect)
    lib/figma_policy.dart          ← regras por tipo, tabelas de ícones e de tokens, componentes ignorados
    docs/                          ← doc opcional por componente (seção 10.3)
    rules/                         ← regras de projeto (seção 10.4)
  carteira_ds_examples/            ← exemplos de implementação: compilam, sem regra de negócio
  carteira_lints/                  ← regras obrigatórias como lint (custom_lint)
  figma_specs/                     ← snapshot da biblioteca (IR + .md + PNGs)
```

O TypeScript fica restrito ao extrator e ao plugin, porque o runtime de plugins do Figma é JavaScript.
Tudo o que o time Flutter consome é Dart ou JSON.

---

## 4. IR v1 — o contrato

Formato próprio e versionado. **Não** copiamos a saída do `get_design_context`: ela é código de referência
para LLM, não é um contrato documentado e pode mudar sem aviso.

### 4.1 Cabeçalho

```json
{
  "irVersion": "1.2.0",
  "kind": "component | screen | flow | library",
  "source": {
    "via": "plugin | mcp-extractor | mcp-native",
    "extractor": "0.3.0",
    "fileKey": "sgwwQGDTn2rhRA1PMaqL5f",
    "fileName": "Carteira DS",
    "pageName": "Components",
    "exportedAt": "2026-10-24T18:00:00Z"
  },
  "intent": { "notes": "texto livre do designer (opcional)" },
  "tokens": { ... },
  "textStyles": { ... },
  "componentRefs": { ... },
  "components": [ ... ],
  "screens": [ ... ],
  "flow": { ... },
  "lint": [ ... ]
}
```

Os blocos são sempre os mesmos. O `kind` só define quais vêm preenchidos (seção 5). `tokens`, `textStyles` e
`componentRefs` trazem só o subconjunto usado no export, para que ele se baste sozinho.

`componentRefs` guarda, por key, o nome e o schema das props de cada componente referenciado:

```json
"componentRefs": {
  "d80c1ef9…": {
    "name": "TransactionItem", "remote": true,
    "props": { "direction": { "type": "VARIANT", "options": ["in", "out"], "default": "in" } }
  }
}
```

### 4.2 Tokens

Indexados por `Coleção/nome`, porque o mesmo nome pode existir em coleções diferentes (`Spacing/sm` e
`Radius/sm`). Cada token traz valor resolvido no modo padrão, alias, code syntax, id e key. Quando a coleção tem
mais de um modo (Light/Dark, marcas, densidade), `modes` traz o valor ou alias de cada modo pelo nome. Um nó que
fixa um modo (uma tela em Dark) leva `modes: { "Theme": "Dark" }`.

```json
"tokens": {
  "Spacing/lg": { "name": "lg", "collection": "Spacing", "type": "FLOAT", "value": 16,
                  "codeSyntax": { "WEB": "var(--spacing-lg)" }, "id": "VariableID:…", "key": "30ef…", "remote": true },
  "Color/text/primary": { "name": "text/primary", "collection": "Color", "type": "COLOR", "value": "#0F172A",
                          "aliasOf": "Primitives/gray/900", "…": "…" }
},
"textStyles": {
  "label": { "name": "label", "fontFamily": "Inter", "fontStyle": "Medium", "fontSize": 14, "lineHeight": 20, "…": "…" }
}
```

Arquivos que usam **estilos de cor** em vez de variáveis (ou os dois) também são cobertos: o nó leva
`style.fillStyle`/`strokeStyle` (ou `text.colorStyle`), e o estilo entra em `paintStyles` com as cores. Se duas
bibliotecas usam o mesmo nome (`Colors/primary` no core e na marca), a segunda recebe o sufixo da key
(`Colors/primary#1a2b3c4d`) e o lint marca `duplicate-name`.

### 4.3 Componentes (biblioteca)

```json
{
  "key": "d80c1ef919ba7685ba72eeac61c7ec49cfba48a1",
  "name": "TransactionItem",
  "description": "Transaction row. direction in/out. …",
  "props": {
    "direction": { "type": "VARIANT", "options": ["in", "out"], "default": "in" },
    "title":     { "type": "TEXT", "default": "Salário" },
    "showBadge": { "type": "BOOLEAN", "default": true }
  },
  "variants": [ { "props": { "direction": "in" }, "tree": { /* nó */ }, "image": "transaction_item/direction=in.png" } ]
}
```

### 4.4 Nós (componentes e telas usam a mesma estrutura)

```json
{
  "id": "7:198",
  "type": "INSTANCE | FRAME | TEXT | VECTOR | …",
  "name": "AppHeader",
  "fidelity": "exact | inferred | unresolved",
  "instance": {
    "componentKey": "3c931b7b…",
    "mainComponentKey": "3c931b7b…",
    "componentName": "AppHeader",
    "props": { "greeting": "Bom dia,", "name": "Ana Souza" },
    "exposed": [ { "path": "Avatar", "componentKey": "a1f0…", "mainComponentKey": "b72c…",
                   "componentName": "Avatar", "props": { "initials": "AS" } } ],
    "overrides": [ { "id": "7:203", "node": "bg", "fields": ["fills"],
                     "values": { "fills": [ { "type": "SOLID", "color": { "token": "Color/success", "value": "#16A34A" } } ] } } ]
  },
  "sizing": { "horizontal": "FILL", "vertical": "HUG" },
  "layout": {
    "direction": "VERTICAL",
    "gap":     { "token": "Spacing/xl", "value": 24 },
    "padding": { "top": { "token": "Spacing/2xl", "value": 32 }, "…": "…" },
    "align": { "main": "MIN", "cross": "CENTER" }
  },
  "style": {
    "fills":  [ { "type": "SOLID", "color": { "token": "Color/bg", "value": "#F8FAFC" } } ],
    "strokes": [ { "type": "SOLID", "color": { "token": "Color/border", "value": "#E2E8F0" } } ],
    "radius": { "token": "Radius/md", "value": 12 }
  },
  "text": { "characters": "Últimas transações", "style": "heading/md", "color": { "token": "Color/text/primary" } },
  "children": [ ]
}
```

`instance.overrides` registra customizações feitas fora das props do componente, **com os valores**. `id` identifica
a camada sem depender do nome; `node` mantém o caminho legível e continua presente para compatibilidade. É assim que o
gerador sabe, por exemplo, que um Avatar foi tingido de `Color/success` mesmo sem existir uma prop para isso.
Também entram texto e visibilidade alterados direto numa camada sem prop ligada (`values.characters`,
`values.visible`), e instâncias aninhadas não expostas que foram trocadas ou configuradas (`values.component`,
`values.props`). Em DS onde nem todo texto virou prop, isso é o que impede o conteúdo de se perder. O que já está
em `props` ou `exposed` não se repete aqui. O
schema completo está em `figma_plugin/schema/ir.v1.schema.json`, gerado de `figma_plugin/src/extractor/ir.ts`.

Toda referência a componente (instância, instância exposta, valor de INSTANCE_SWAP) traz duas keys:

- **`componentKey`:** do component set (ou do componente, se não tem variants). É por ela que se acha o `.figma.dart`.
- **`mainComponentKey`:** do componente principal exato, ou seja, a variant usada. Num set `Icon` com uma variant
  por ícone, todos os ícones têm a mesma `componentKey` e uma `mainComponentKey` diferente. É ela que identifica o
  ícone (ou qualquer variant mapeada à parte) sem depender do nome.

`exposed` inclui instâncias expostas em qualquer nível. Por exemplo, as `Flag` que um `.Nested / Global Switcher`
expõe dentro do componente pai, com `path` `.Nested / Global Switcher/1. Flag`.

Regras:
- Todo valor que veio de variável carrega `token` **e** `value`. Valor sem `token` é valor solto no design, e o lint aponta.
- `fidelity` é obrigatório. É ele que decide como o gerador trata o nó (seção 9).

### 4.5 Fluxo e lint

```json
"flow": {
  "start": "7:135",
  "edges": [
    { "from": "7:135", "trigger": { "node": "7:180", "name": "Button/Entrar", "type": "ON_CLICK" },
      "to": "7:197", "action": "NAVIGATE", "transition": "SMART_ANIMATE" }
  ]
},
"lint": [ { "node": "7:251", "rule": "raw-color", "detail": "preenchimento sem variável nem estilo" } ]
```

`flow.edges` sai direto das `reactions` do protótipo. `to: "back"` representa a ação Back.

---

## 5. Casos de uso e tipos de export

Um único formato atende todos os casos. Muda o **escopo** (o que foi selecionado) e a **profundidade** (o quanto
de cada nó entra).

### 5.1 Casos de uso

| # | Caso | Seleção no Figma | `kind` | O que o dev recebe |
|---|---|---|---|---|
| 1 | Componente novo no DS | component set no arquivo do DS | `component` | todas as variants e props, árvore interna, componentes do DS usados dentro, tokens, imagem por variant |
| 2 | Tela nova | 1 frame | `screen` | árvore de instâncias do DS com props e overrides, layout entre elas, tokens, o que não é DS, imagem |
| 3 | Fluxo novo | 2+ frames ou uma section | `flow` | o caso 2 para cada tela + navegação (`flow.edges`) e ponto de início |
| 4 | Componente local de feature | component no arquivo do produto | `component` | igual ao caso 1, com destino na pasta da feature, não no DS |
| 5 | Alteração em componente ou tela existente | o mesmo nó exportado antes | o do nó | export novo, comparado ao anterior pelos ids |
| 6 | Estados de uma tela | frames `Tela / loading`, `Tela / vazio`… | `screen`/`flow` | variações agrupadas como estados de **uma** tela |
| — | Snapshot do DS | nada selecionado, no arquivo do DS | `library` | todos os tokens, text styles e componentes |

Além disso, o plugin roda o **lint** em qualquer export e mostra o relatório antes de exportar.

### 5.2 Regra de profundidade

| Tipo de nó | Como entra |
|---|---|
| Instância de componente **de biblioteca**: remoto, ou local e publicado | **rasa**: key, nome, props usadas, instâncias expostas e overrides. A estrutura interna não entra: o widget já existe |
| Componente **exportado**, ou componente local **não publicado** usado na tela | **profundo** em `components`: árvore completa, todas as variants. Na tela, entra como referência rasa |
| Frame de layout (cola entre componentes) | completo: direção, gap, padding, sizing, tokens |
| Valor solto, instância detached, componente de fora do DS | completo, e marcado no `lint` |

Assim uma tela com 40 componentes gera um export pequeno, e um componente novo gera um export detalhado, com o
mesmo extrator.

O critério é o status de publicação (`getPublishStatusAsync`), não "estar no mesmo arquivo". Assim um template
montado **dentro do arquivo do DS** não arrasta os componentes do DS para o export: eles são locais, mas
publicados. Componentes de feature, que não são publicados, continuam saindo em profundidade.

### 5.3 Como o `kind` é inferido

| Seleção | `kind` |
|---|---|
| Component set, component ou variant (sobe para o set) | `component` |
| 1 frame | `screen` |
| 2+ frames, ou uma section (as telas são os frames dentro dela) | `flow` |
| Nada selecionado | `library` (componentes da página atual + todos os tokens locais) |

O plugin mostra o `kind` inferido e permite trocar antes de exportar. Pelo MCP, o agente passa os ids no lugar
da seleção e pode forçar o `kind`.

### 5.4 Estados de tela

Frames nomeados `Tela / estado` são agrupados numa tela só, com `states: ["default", "loading", …]`. Frame sem
`/` é o estado `default`.

### 5.5 Alterações (caso 5)

**Decisão:** o export novo é comparado com o **export anterior commitado** no repositório, pelos ids dos nós.
Nada é guardado no arquivo do Figma. Motivo: guardar estado no Figma exigiria `setPluginData`, que o `use_figma`
não permite. Comparar com o commitado mantém o plugin e o MCP iguais.

### 5.6 Saída

- **Plugin:** um `.zip` com `export.json` e `images/*.png`, ou "copiar JSON".
- **MCP:** o JSON volta no `return` do `use_figma`, sem imagens. As imagens vêm da ferramenta `get_screenshot`.

### 5.7 Limite do MCP e paginação

O `use_figma` rejeita retornos acima de **48 000 bytes** e código acima de 50 000 caracteres. Medido no POC: o
fluxo de 5 telas gera ~119 KB de IR formatado (~60 KB compacto).

- O bundle do extrator (`dist/mcp-extractor.js`) tem ~21 mil caracteres; o build falha se passar de 48 mil.
- Quando o IR não cabe, `F2D.run` devolve `{ page: 0, pages: N, exportedAt, data }`. O agente chama de novo com
  `page: 1…N-1` **e o mesmo `exportedAt`**, concatena os `data` em ordem e faz `JSON.parse`.
- As páginas são cortadas pelo tamanho em bytes do texto já escapado, então cada uma cabe no limite.
- Fixar o `exportedAt` torna as execuções idênticas byte a byte; sem isso, as páginas não se encaixariam.
- Cada página reexecuta a extração inteira. Para exports grandes (uma biblioteca de centenas de componentes), o
  agente deve dividir em lotes de `nodeIds` (por component set ou por página) em vez de paginar um IR enorme.

### 5.8 O que é geral e o que é convenção

O extrator não conhece nenhum componente, token ou nome do nosso DS: lê só a Plugin API. Antes de usar num DS
maior, o que muda é isto:

| Situação em DS maiores | Como o extrator trata |
|---|---|
| Temas e marcas por modos de variável | `tokens[].modes` e `node.modes` (4.2) |
| Estilos de cor em vez de variáveis | `fillStyle`/`strokeStyle`/`colorStyle` + `paintStyles`; não acusa `raw-color` |
| Core + marca com nomes iguais | sufixo da key + `duplicate-name` |
| Texto sem prop, camada escondida sem prop, instância aninhada não exposta | `overrides[].values` (4.4) |
| Templates dentro do arquivo do DS | componentes publicados ficam rasos (5.2) |
| Sections aninhadas | as telas são procuradas em qualquer nível; a ordem usa a posição absoluta no canvas |
| Auto layout em grid, min/max, tamanho ligado a variável | `layout.grid`, `limits`, `sizeTokens` |
| Ícones e ilustrações sem auto layout | não acusam `absolute-layout` |
| Centenas de variáveis sem code syntax | uma única entrada de lint com a contagem |

Continuam sendo **convenções** (afetam só agrupamento e lint, não perdem dados):

- **Estados `Tela / estado`.** Um arquivo que usa `/` para categorizar (`iOS / Home`) agrupa errado; `frameName`
  guarda o nome original, então o gerador consegue corrigir.
- **Biblioteca por página.** `kind: library` lê os componentes da página atual. Num DS com uma página por
  componente, exporte página a página.
- **Variáveis de tipografia direto no texto,** sem text style, saem como fonte solta (`font`) e o lint acusa
  `text-without-style`. Variáveis ligadas ao próprio text style são cobertas pelo nome do estilo.

---

## 6. Entradas: três caminhos para o mesmo IR

### 6.1 Extrator compartilhado (plugin e MCP)

O `use_figma` do MCP executa a **mesma Plugin API** de um plugin. Por isso um único `extract.ts` roda nos dois
lugares e produz IR idêntico. O extrator usa só a interseção das duas APIs e recebe um adaptador de I/O de cada lado:

| | Plugin | MCP (`use_figma`) |
|---|---|---|
| Saída | download / copiar pela `figma.ui` | `return`, com limite de tamanho: o extrator pagina em lotes |
| Imagens | `node.exportAsync()` | ferramenta `get_screenshot` |
| Páginas | livre | trocar de página no máximo uma vez por chamada |
| APIs proibidas | — | `loadAllPagesAsync`, `setPluginData`, `createImageAsync`, `figma.notify` |

### 6.2 MCP nativo (sem o extrator)

Para quem só usa `get_design_context` + `get_metadata` + `get_variable_defs`. O **importer MCP** reconstrói o IR
a partir desses três artefatos. Teste feito na tela `02 · Dashboard` do arquivo de fluxo:

| Dado do IR | Origem no MCP nativo | Fidelidade |
|---|---|---|
| Hierarquia e ids | `get_metadata` (XML) | exact |
| Componente usado 2+ vezes, com props | vira função tipada: `<TransactionItem direction="out" showBadge={false} …/>` | exact (por nome) |
| Componente usado 1 vez | "achatado" em `<div data-name="…">`, sem props | inferred, via `data-name` × nomes do DS |
| Variant de componente achatado | comparar as classes com o snapshot da biblioteca | inferred |
| Ícone | vira URL temporária de SVG, sem nome | unresolved |
| Layout | classes Tailwind (`flex-col`, `gap-[var(--x)]`, `w-full`) | exact |
| Tokens | `var(--spacing-md)` + `get_variable_defs` (exige code syntax WEB) | exact |
| Schema completo das props | só aparecem as variants **usadas** | vem do snapshot da biblioteca |

### 6.3 Resumo

| Entrada | Quem usa | Fidelidade |
|---|---|---|
| Plugin | designer, sem Dev Mode | exata |
| MCP + extrator (`use_figma`) | agente / CI | exata |
| MCP nativo | qualquer pessoa com MCP | melhor esforço, com relatório |

---

## 7. Mapeamento Figma → Dart (`*.figma.dart`)

Substitui o Code Connect. Um arquivo por componente, num pacote separado (`carteira_ds_figma`).
**O widget do DS não é alterado.**

Referência completa da anotação (tipos de componente, política por tipo, `figmaNotes`, `devNotes`, `Doc`, `Example`,
`status`, validação): [FIGMA_CONNECT.md](FIGMA_CONNECT.md). Esta seção resume as decisões.

```dart
// carteira_ds_figma/lib/connect/ds_button.figma.dart
@FigmaConnect(key: 'cc4d255d4c889786852f8ba4b57a714a4efd07ca', name: 'Button')
Widget button(FigmaProps f) => DsButton(
  label: f.text('label'),
  variant: f.variant('variant', {
    'primary': DsButtonVariant.primary,
    'secondary': DsButtonVariant.secondary,
    'ghost': DsButtonVariant.ghost,
  }),
  size: f.variant('size', {'md': DsButtonSize.md, 'sm': DsButtonSize.sm}),
  leftIcon: f.boolean('showLeftIcon') ? f.icon('leftIcon') : null,
  onPressed: f.variant('state', {'default': () {}, 'disabled': null}),
);
```

### 7.1 API do `FigmaProps`

| Método | Prop do Figma | Retorno |
|---|---|---|
| `text(name)` | TEXT | `String` |
| `boolean(name)` | BOOLEAN | `bool` |
| `variant(name, map)` | VARIANT | valor do `map` |
| `icon(name)` | INSTANCE_SWAP de ícone | `DsIconName`, pela `mainComponentKey` do ícone; sem entrada na tabela, pela convenção de nomes |
| `instance(name)` | INSTANCE_SWAP / instância exposta | `Widget`, resolvido recursivamente pelo mapeamento dela |
| `nested(path)` | instância exposta sem mapeamento próprio (ex.: `.Nested / Global Switcher/1. Flag`) | `FigmaProps` dela, para o pai ler as props (`f.nested('1. Flag').boolean('Disabled')`) |
| `slot(part)` | área livre de um template (ex.: o corpo da lista) | `Widget`, gerado recursivamente a partir da árvore do IR |
| `guided(param, guide:, or:)` | nenhuma: parte que exige julgamento | o valor `or`, que compila; o gerador escreve o marcador `f2d:guided` com o `guide` (7.6) |

### 7.2 Casos de nome de componente

| Caso | Exemplo | Como declarar |
|---|---|---|
| Nome diferente, 1:1 | `Btn` → `DsButton` | `@FigmaConnect(key: …, name: 'Btn')` |
| 1 do Figma → N widgets | `Button type=icon-only` → `DsIconButton` | duas funções, cada uma com `when: {'type': 'icon-only'}` |
| N do Figma → 1 widget | `Card/Small` + `Card/Large` → `DsCard(size:)` | uma função por componente; o corpo fixa o valor (`DsCard(size: DsCardSize.small)`) |
| Só existe no Figma | `_Base/Shape` | prefixo `_` ou `.` = ignorado; outros casos na lista `ignored` com motivo |

### 7.3 Por que funciona

- **Segurança de tipos:** o arquivo instancia o widget de verdade. Renomear ou remover um parâmetro no DS quebra
  a compilação do `carteira_ds_figma`.
- **Serve de template:** o gerador avalia a função trocando `f.*` pelos valores da instância (seção 9).
- **Serve de teste visual:** rodada com as props de cada variant, renderiza o widget para o golden test.

### 7.4 Cuidado

O mapeamento está num pacote separado, então quem altera o DS pode quebrá-lo sem perceber. Os dois pacotes
rodam na **mesma CI**: um PR no DS também roda `dart analyze` no `carteira_ds_figma`.

### 7.5 Alternativa descartada: anotar o próprio widget

`@FigmaComponent` / `@FigmaProp` direto no `DsButton` daria o mesmo resultado, sem custo em runtime
(anotação é metadado `const`, descartado no AOT). Foi descartada para **não alterar os componentes existentes**.

### 7.6 Cobertura parcial: o norte para a LLM

Nem todo componente tem correspondência 1:1 com o Figma, principalmente os templates. A anotação cobre o que é
determinístico e, para o resto, deixa um **norte**: a direção a seguir, deixando claro que a LLM vai ter que decidir
como construir aquela parte.

```dart
@FigmaConnect(
  key: '9f2c…',
  name: 'Template / Lista com filtro',
  coverage: Coverage.partial,
  guide: 'Lista paginada. O template já traz o AcmeScaffold; filtros e refresh dependem da feature.',
  figmaNotes: {
    'state': 'Não existe no código: o vazio vem de items: [] + empty:',
    'Collapse': 'Só visual no Figma; ignorar.',
  },
  devNotes: [
    DevNote.must('Sempre dentro de um AcmeContext com `feature` definido.'),
    DevNote.must('Não envolver em outro AcmeScaffold.', lint: 'acme_single_scaffold'),
    DevNote.prefer('Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.'),
  ],
)
Widget listaComFiltro(FigmaProps f) => AcmeListPage(
  title: f.text('Title'),                                   // coberto
  itemBuilder: f.slot('content'),                           // coberto, gerado recursivamente
  filters: f.guided('filters',
    guide: 'Cada Flag exposta vira AcmeFilterChip; Disabled → enabled: false.',
    or: const []),
  onRefresh: f.guided('onRefresh',
    guide: 'Só existe no código. Obrigatório se a lista vem da API: chamar o refresh do cubit.',
    or: () async {}),
);
```

*(Exemplo ilustrativo: os nomes do DS real entram quando os mapeamentos forem escritos.)*

| Campo | Responde | Vale para |
|---|---|---|
| `coverage` | `complete`, `partial` ou `sketch` (abaixo) | o componente |
| `guide` | o que é o componente e o que falta cobrir | o componente |
| `figmaNotes` | como interpretar uma prop do Figma que não vira parâmetro (deriva de outra coisa, ou ignorar) | uma prop do Figma |
| `f.guided(param, guide:, or:)` | como preencher um parâmetro que exige julgamento; `or` é o valor provisório que compila | um parâmetro do código |
| `f.slot(part)` | área livre gerada recursivamente; só o que não tiver mapeamento lá dentro vira lacuna | uma parte do template |
| `devNotes` | regras de uso no código que valem sempre que o componente aparece | o componente, em qualquer tela |

**Quando não vale mapear: `FigmaConnect.sketch`.** Para um componente do DS que não se quer tratar de forma
determinística (o conteúdo do template são camadas, não props), a anotação **não tem builder**: anota um `typedef`
que liga o componente do Figma à classe do DS e dá o norte. O construtor exige `guide` em compilação:

```dart
@FigmaConnect.sketch(
  key: 'e5eab15a…', name: 'Template / Extrato', kind: FigmaKind.template,
  guide: 'Cada grupo de dia do Figma vira um DsStatementDay; o resumo vira incomeTotal/expenseTotal.',
  docs: [Doc.path('carteira_ds_figma/docs/ds_statement_template.md')],
  examples: [Example.code('carteira_ds_examples/lib/statement_example.dart', symbol: 'StatementExample')],
)
typedef StatementTemplate = DsStatementTemplate;
```

A diferença para o `partial` é o contrato com a LLM: no `partial` o código gerado é final fora das lacunas
marcadas; no `sketch` não há código: a instância vira o placeholder `f2d:sketch` e uma tarefa de montagem com brief
próprio (`components/<nome>/BRIEF.md`): norte, **API do widget** lida do código do DS pelo analyzer (construtores,
parâmetros, tipos auxiliares), **dados de cada instância** no Figma, docs e exemplos. O Carteira DS tem um caso de
cada: `TransactionList` (`partial`) e `Template / Extrato` (`sketch`).

**`devNotes` independe da cobertura.** Um componente totalmente coberto também pode ter regras (ex.: no Button, "em
fluxo de pagamento, nunca `onPressed: null`; usar `state: disabled`"). São de dois tipos:

- **`DevNote.must(texto, lint:)`:** obrigatório. Se for verificável, aponta o lint que cobra a regra: o texto
  orienta, o lint garante.
- **`DevNote.prefer(texto)`:** recomendação. A LLM pode fugir, mas marca com `f2d:inferred` e diz o motivo.

**Limites do que vai na anotação:**

- Frases curtas (até ~2 linhas). Exemplo completo, motivo de uma regra e erros comuns vão no doc do componente (10.3).
- Regra que fala da tela ou de vários componentes ("toda tela de feature usa AcmeContext") é regra de projeto
  (10.4), não `devNotes`; senão seria copiada em 12 templates.

**Cobertura calculada, não declarada.** A CLI compara o que a instância usa no IR com o que a anotação lê:

| Item da instância no IR | Coberto quando | Se não for coberto |
|---|---|---|
| Prop (TEXT, BOOLEAN, VARIANT, SWAP) | a anotação lê com `f.text`, `f.boolean`… | lacuna, com o `figmaNotes` da prop ou sem norte |
| Instância exposta | a anotação usa `f.instance` ou `f.nested` | idem |
| Override fora da API do componente | nunca (a anotação não lê overrides) | lacuna, com os valores do override |
| `f.guided` | nunca (é proposital) | lacuna com o `guide` |

E valida a anotação contra o IR e o doc:

- `coverage: complete` com prop do Figma não lida → **erro**.
- `coverage: partial` sem nenhum `guided` nem `figmaNotes` → **erro** (parcial sem norte).
- `FigmaConnect.sketch` sem `guide` não compila; anotando uma função em vez de um `typedef`, é **erro** da CLI.
- Prop do Figma sem leitura, sem `figmaNotes` e sem `ignored` → **erro**.
- Seção do doc sobre uma prop que a anotação passou a cobrir → **aviso** (doc desatualizado).
- `guide` ou nota longa → **aviso** para mover o detalhe para o doc.
- Mesma `devNote` em vários componentes → **sugestão** de virar regra de projeto; `must` sem `lint` que se repete →
  candidato a lint.

**Template desanexado.** Se o designer copiar e desanexar o template, não há instância nem props e a anotação não
roda. O `detachedInfo` do IR ainda diz de qual template a tela veio: a CLI entrega o `guide`, as notas e o doc
inteiros desse template, mais a árvore do IR, e a LLM monta o template a partir disso. O lint do plugin avisa o
designer.

---

## 8. Nomes

Os nomes divergem em todos os níveis. Casos reais deste POC:

| Nível | Figma | Dart |
|---|---|---|
| Componente | `Button` | `DsButton` |
| Prop | `showLeftIcon` + `leftIcon` | `leftIcon` (nulo = escondido) |
| Valor de variant | `direction=in` | `DsTransactionDirection.incoming` |
| Estado | `state=disabled` | `onPressed: null` |
| Token | `spacing/2xl`, `text/primary` | `DsSpacing.xxl`, `DsColors.textPrimary` |
| Ícone | `arrow-up-right` | `DsIconName.arrowUpRight` |
| Text style | `heading/lg` | `DsTextStyles.headingLg` |

Regras:

1. **Identidade por chave, nunca por nome.** O casamento usa a `key` do componente e o id/key da variável. O nome é
   só para humanos. Renomear no Figma não quebra nada; a checagem de drift só informa.
2. **Convenção primeiro, exceção explícita depois.** Uma função `toDartName` determinística (separa por espaço, `/`,
   `-` e `_`, depois aplica camelCase) resolve a maioria. Onde não resolve, declara-se a exceção:
   - no `.figma.dart`, pelo `map` do `variant`;
   - em `figma_specs/naming.yaml`, para tokens e ícones (ex.: `2xl → xxl`, porque identificador Dart não começa com número).
3. **Aliases para inconsistências do próprio Figma** (`Medium`/`M`/`md` → `md`). Comparação sempre normalizada
   (caixa e separadores). As inconsistências aparecem no relatório como dívida de design.
4. **Sufixo de prop removido:** a API devolve `label#4:0`; o normalizador remove `#…`.

---

## 9. Geração e drift

### 9.1 `figma2dart generate <tela>`

1. Lê o nó da tela no IR.
2. Para cada instância, encontra o `.figma.dart` pela `mainComponentKey` (mapeamento de uma variant específica) e,
   se não houver, pela `componentKey` (ou pelo nome, no MCP nativo). Avalia o template com os valores da instância.
   Instâncias expostas e aninhadas seguem a mesma busca. Argumentos iguais ao default do construtor são removidos.
3. Frames de layout viram `Column`/`Row`/`Padding` com os tokens (`DsSpacing.xl`), nunca valores crus.
4. Classifica cada nó em **do DS** ou **fora do DS** (10.5). O que está fora do DS vira `// f2d:placeholder`, com o
   tamanho do Figma; override fora da API de um componente do DS é ignorado (fica o valor padrão) e também marcado
   como placeholder.
5. Trata a fidelidade de cada nó:
   - `exact`: gera o código direto.
   - `inferred`: gera o código com `// f2d:inferred` (valor deduzido, o revisor confere).
   - `unresolved`: gera um placeholder com `// f2d:gap`.
6. Componente parcial (7.6): preenche o que está coberto e escreve `// f2d:guided` com o `guide` em cada
   `f.guided`. Prop não coberta e componente do DS sem anotação viram `// f2d:gap`. Componente `sketch` vira o
   placeholder `f2d:sketch` e uma tarefa de montagem com brief próprio (API do widget e dados do Figma).
7. Roda `dart format` + `dart analyze`. O rascunho **sempre compila**.

O que sobra em `f2d:guided`, `f2d:gap` e `f2d:sketch` é trabalho da LLM, com o brief da seção 10. `f2d:placeholder` é do dev.
O núcleo continua determinístico.

### 9.2 `figma2dart drift`

Compara o snapshot da biblioteca com os mapeamentos:

| Situação | Severidade |
|---|---|
| Mesma key, nome diferente | info |
| Valor de variant sem mapeamento | erro |
| Prop nova no Figma sem leitura no `.figma.dart`, sem `figmaNotes` e sem `ignored` | erro |
| Componente publicado sem mapeamento | aviso (vira a métrica de cobertura) |
| Parâmetro removido no DS | erro de compilação no `carteira_ds_figma` |

### 9.3 `figma2dart components`

Lista os componentes da biblioteca com status (mapeado / sem mapeamento / ignorado) e **sugere** o widget provável
por similaridade de nome e de assinatura de props. A sugestão nunca vira mapeamento sozinha: um dev confirma
escrevendo o `.figma.dart`.

---

## 10. Geração assistida por LLM

O que é determinístico, a LLM recebe pronto (seção 9). O que não é, ela implementa seguindo o norte das anotações
(7.6) e os docs, e marca o que decidiu. Para a LLM vai só o que exige julgamento, e só o que vale para a tela da
tarefa: um documento único com todas as regras de 300 componentes é o que mais faz um modelo errar.

### 10.1 Três tipos de conhecimento

| Tipo | Exemplo | Onde fica | Como chega na LLM |
|---|---|---|---|
| **Obrigatório** | toda tela usa `AcmeScaffold` dentro de `AcmeContext` | gerador (`@FigmaScreen`) e lint | já vem no rascunho; se ela quebrar, o `analyze` acusa |
| **Com julgamento** | como montar os filtros de uma lista, qual configuração de contexto usar | `guide`, `figmaNotes`, `f.guided`, `devNotes` (7.6), doc (10.3) e regras de projeto (10.4) | só o que vale para a tela, no brief |
| **Visual** | layout, componentes do DS, tokens | IR | rascunho gerado |

### 10.2 Componentes que só existem no código

`AcmeContext`, `AcmeScaffold` e similares não estão no Figma e não precisam estar:

- **Valem para toda tela:** entram pelo mapeamento de tela, sempre aplicado pelo gerador.

  ```dart
  @FigmaScreen()
  Widget screen(FigmaScreenProps s) => AcmeContext(
    child: AcmeScaffold(
      appBar: s.instance(appHeader),     // a função anotada do AppHeader (achada pela key, não pelo nome)
      body: s.body(),                    // o resto da árvore gerada
    ),
  );
  ```

- **Dependem do template:** vão na anotação do template (`devNotes`, `f.guided`).
- **Dependem da feature:** viram uma pergunta explícita no brief, para a LLM resolver olhando o código da feature.

### 10.3 Doc de componente (opcional)

O norte curto fica na anotação. O doc é para o que não cabe em uma linha: exemplo completo, erros comuns, motivo de
uma regra. Fica em `carteira_ds_figma/docs/<componente>.md`, mantido por quem mantém a anotação, de preferência no
mesmo PR.

- **Organizado pelas partes da anotação.** Uma seção `## Geral` e uma seção por parte, com o mesmo nome usado no
  `f.guided` e no Figma (`## filters`, `## onRefresh`). O brief recorta só as seções das lacunas da tela.
- **Não guarda o que já existe em outro lugar.** Construtor, tipos e defaults a CLI lê do Dart; props e variants,
  do IR. O doc guarda só o que uma pessoa sabe e o código não diz. Cabe em ~40–60 linhas.
- **Não confundir** com `figma_specs/components/*.md` (seção 11), gerado do Figma.
- **Produção:** `figma2dart docs init <componente>` cria o esqueleto; uma LLM rascunha a partir do código do widget e
  de **usos reais nos apps**, e um dev do DS revisa. `figma2dart docs status` lista os componentes usados nos exports
  sem anotação ou sem norte, ordenados por frequência: templates e os 20–30 mais usados primeiro.

### 10.4 Regras de projeto

Regras que falam da tela ou de vários componentes. Um arquivo por regra em `carteira_ds_figma/rules/`, com um
cabeçalho que a CLI avalia para decidir se a regra entra no brief:

````markdown
---
id: forms.validation
applies_when: { uses: [Input] }          # ou { has: flow }, { template: Lista }, always
enforced_by: none                        # ou lint:<id>
---
Validação de formulário usa `AcmeForm` + `AcmeValidators`, nunca `TextFormField.validator` direto.

✅ DsInput(state: form.error('senha') ? .error : .default_, helper: form.message('senha'))
❌ if (senha.isEmpty) setState(() => erro = 'Obrigatório')
````

Uma tela de login recebe 4 ou 5 regras, não 80. Regra obrigatória e verificável vira lint em `carteira_lints`
(`custom_lint`): é o jeito mais confiável de passar uma regra para um modelo, porque devolve o erro com a linha.

### 10.5 Marcadores no código

| Marcador | Significa | Quem escreve | Quem resolve |
|---|---|---|---|
| `// f2d:guided Gn <parte> — <guide>` | parte com norte, decisão da LLM | gerador | LLM |
| `/* f2d:sketch <componente> → <Widget> */` | componente do DS sem mapeamento (`FigmaConnect.sketch`): placeholder até a LLM montar o widget pelo brief da tarefa (API, dados do Figma, norte) | gerador | LLM (marca o que decidiu com `f2d:inferred`) |
| `/* f2d:local <componente> → <Widget> */` | widget do app que já existe (`@FigmaLocal`, FIGMA_CONNECT §5.1): placeholder até a LLM montar o widget pelo brief da tarefa (API, `import`, dados do Figma) | gerador | LLM |
| `// f2d:gap Gn — <motivo>` | sem norte: componente sem anotação, prop não coberta, override fora da API, nó `unresolved` | gerador | LLM |
| `// f2d:inferred Gn — <motivo>` | valor não confirmado: decisão da LLM, `prefer` não seguido, ou IR `inferred` | LLM ou gerador | revisor |
| `// f2d:placeholder Pn <tipo> — <nome> (<id>, <key>)` | fora do DS: fica um placeholder ou o valor padrão | gerador | dev (no futuro, a feature de construção) |
| `/* TODO(f2d): <motivo> */ <valor provisório>` | ícone do Figma que não existe no enum do DS (fica o primeiro valor), imagem ou vetor sem arquivo no export (fica um `Placeholder` do tamanho do nó) | gerador | dev; o `check` lista e não reprova |

O gerador copia o `guide` e os valores do Figma para o marcador, então a orientação está na linha que precisa mudar:

```dart
// f2d:guided G2 filters — Cada Flag exposta vira AcmeFilterChip; Disabled → enabled: false.
//   Figma: 1. Flag {Rounded: true, Disabled: false, Currency: BRL}, 2. Flag {…, Currency: Global}
filters: const [],
```

**Do DS ou fora do DS.** A classificação é feita pelo gerador, num único lugar:

| No IR | Classificação | Código gerado |
|---|---|---|
| Instância cuja key está no retrato da biblioteca do DS (`figma_library.json` no pacote de mapeamentos, gravado por `figma2dart library`; sem retrato: instância remota) | do DS | o mapeamento; sem mapeamento, `f2d:gap` |
| Instância com `@FigmaLocal` no pacote ou numa dependência por path dele | do app | `f2d:local` + tarefa de montagem |
| Frame de layout: sem estilo próprio, só com itens do DS, texto com text style do DS e outros frames de layout | do DS | `Column`/`Row`/`Padding` com tokens |
| Instância de componente fora do retrato e sem `@FigmaLocal` (componente local, outra biblioteca) | fora do DS | placeholder + brief de construção (`existing` se uma classe de mesmo nome já existe) |
| Bloco desenhado à mão: frame ou grupo sem instância do DS dentro e com estilo próprio (parecido com um componente do DS ou com estrutura própria) | fora do DS | placeholder |
| Vetor, imagem ou forma solta | fora do DS | placeholder |
| Override fora da API numa instância do DS (ex.: Avatar tingido) | DS com valor padrão | a instância sem o override + marcador |

O critério do "bloco desenhado à mão" é inicial e será ajustado no piloto com telas reais.

O placeholder usa o `Placeholder` do Flutter, sem dependência nova, e mantém o tamanho do Figma para o layout em
volta continuar certo:

```dart
// f2d:placeholder P1 component — ContactItem (7:338, key 5d1e…)
const SizedBox(width: 343, height: 64, child: Placeholder()),
```

**Limites da LLM no escopo atual:** não substitui placeholders nem cria widgets; nunca altera um widget do DS e
nunca usa valor solto (só tokens). Sem norte numa parte do DS, usa o componente do DS mais próximo e marca
`f2d:inferred`.

### 10.6 `figma2dart resolve --screen <tela>` (o brief)

Gera a pasta da tarefa `.figma2dart/tasks/<tela>/` (`BRIEF.md`, `gaps.json`, `refs/<tela>.png`) e escreve o rascunho
no caminho do app. O `BRIEF.md` é o único ponto de entrada da LLM:

```markdown
# Tarefa: tela Login (figma 7:135)
Arquivo: lib/features/auth/login_page.dart (rascunho gerado, compila)
Referência visual: refs/login.png

## Lacunas
- G1 (guided) onPressed de "Entrar" — norte: … · Figma: … · doc: …
- G2 (gap) gráfico de gastos — sem componente no DS · Figma: subárvore 7:210

## Componentes desta tela
### Lista com filtro (parcial)
- [obrigatório] Sempre dentro de um AcmeContext com `feature` definido.
- [obrigatório · lint acme_single_scaffold] Não envolver em outro AcmeScaffold.
- [recomendado] Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.

## Regras desta tela
(as regras de projeto selecionadas)

## Placeholders (não mexer: pendência do dev)
- P1 ContactItem (component fora do DS) · P2 ilustração (vetor)

## Não fazer
- Não substituir placeholders nem criar widgets.
- Não alterar widgets do DS nem criar variações deles; não usar cor/espaçamento solto.

## Pronto quando
`figma2dart check login` passa.
```

- **Componentes desta tela:** os `devNotes` de **todos** os componentes presentes (uma vez por componente, não por
  instância), e `guide` e construtor atual dos parciais. Componentes completos sem `devNotes` não aparecem.
- **Lacunas:** cada uma com o norte, os valores do Figma, o recorte do IR e a seção do doc, quando houver.

**Brief de construção (componentes fora do DS).** Cada componente fora do DS da tela ganha
`components/<nome>/BRIEF.md` (+ `component.json`) na pasta da tarefa, num padrão fixo:

1. cabeçalho: key, id, `description` do Figma; construir só se o usuário escolher;
2. onde criar: `widgets/<nome>.dart` **na pasta do arquivo da tela**, classe `PascalCase` do nome do Figma;
3. API proposta: construtor tirado das props do Figma (TEXT → `String`, BOOLEAN → `bool`, VARIANT → enum,
   INSTANCE_SWAP → `Widget`);
4. variantes com PNG (quando há mais de uma);
5. estrutura de cada variant: layout e estilo pelo nome do token, textos com a prop ligada, instâncias do DS **já
   resolvidas pelos mapeamentos** e link para o brief de outro componente local usado dentro;
6. usos na tela: os valores das props em cada instância;
7. decisões e regras (só tokens e DS, um teste por variant, `f2d:inferred` no que foi decidido).

O `BRIEF.md` da tela lista os componentes em "Componentes a construir", dependências primeiro. Implementado na
fase 1 do `figma2dart resolve`.

### 10.7 `figma2dart check <tela>`

Critério de pronto objetivo, que a LLM roda em ciclo até passar:

1. Nenhum `f2d:guided`, `f2d:gap`, `f2d:sketch` ou `f2d:local` restante. `f2d:placeholder` não bloqueia: é pendência do dev.
2. `dart analyze` limpo, incluindo `carteira_lints`.
3. Golden test da tela igual ao PNG do export, dentro da tolerância, **com as áreas de placeholder mascaradas**.

O relatório traz a **porcentagem determinística** da tela, a lista de `f2d:inferred` e a lista de placeholders: o
revisor olha esses pontos, não a tela inteira.

**Dicas (`hints`), que informam e não reprovam.** A regra da casa é avisar a LLM com a sugestão e deixar a decisão
com ela: valor solto (com o token do mesmo valor, pelo contexto: `EdgeInsets` → espaçamento, `circular` → raio; cor
semântica antes da primitiva), widget a montar que sumiu, parâmetro da API proposta ausente no construtor, texto fixo
do Figma ausente. A LLM corrige ou deixa `f2d:inferred` com o motivo. O que esperar vem do `check.json` que o
`resolve` grava em cada tarefa.

### 10.8 Ciclo de melhoria

O determinístico cresce com o uso:

- Erro que se repete no review → linha no doc ou nova `devNote`.
- Lacuna resolvida do mesmo jeito em várias telas → vira código na anotação (sai o `f.guided`).
- `must` sem lint que se repete → vira lint.

O relatório do `check`, agregado por template, mostra quais lacunas mais aparecem: é a lista de prioridades do time
do DS.

### 10.9 Distribuição

Copilot, opencode e Claude Code entendem **skills** (`SKILL.md`) e **servidores MCP**. A entrega usa só isso:

| Peça | O que é |
|---|---|
| `figma2dart` (CLI Dart) | todo o trabalho determinístico; `figma2dart setup` (ou `rake figma2dart:setup`) põe o comando no PATH uma vez por máquina |
| agente `figma-to-flutter` | orquestrador (`.github/agents/`): roda a CLI com `--json`, pergunta ao usuário só o que é escolha dele, delega componentes ao subagente `figma-component-builder` e fecha com o `check` |
| skills | `figma2dart-setup` (caminhos e config), `figma2dart-screen` (tela a partir do brief), `figma2dart-component` (componente fora do DS), em `.agents/skills/` (Copilot e opencode leem) |
| `figma2dart init` | num app só: `figma2dart.yaml`, `.figma2dart/` no `.gitignore`, agente e skills |

**Quem opera a CLI é o agente.** Os caminhos vêm da CLI, não da pessoa: o pacote alvo é a pasta do `pubspec.yaml`
mais próximo (ou `--package`; `figma2dart packages <texto>` acha um pacote pelo nome), o export é o
`figma2dart-*.zip` mais novo da pasta de exports, e a pasta das telas é perguntada uma vez e gravada no config.

**Monorepo, sem caminho fixo.** O comando instalado não é uma cópia da CLI: a cada chamada usa a CLI do repositório
git de onde foi chamado, achada pelo índice do git (`**/bin/figma2dart.dart`), e roda com `dart run` de dentro dela
(executável em cache, recompilado sozinho depois de um `git pull`; o "Building…" vai para o stderr e o stdout fica só
com o JSON). Do mesmo jeito a CLI acha o config do repositório (o `figma2dart.yaml` versionado que tem `mappings:`;
o `figma2dart.yaml` de um pacote, opcional, vence) e o pacote de mapeamentos (`mappings:`, a dependência do pacote
com `lib/connect`, ou o único pacote com `lib/figma_policy.dart`). Pacote sem `package_config` (fora do melos) ganha
`pub get` automático. Detalhes e o caso do <monorepo>: [docs/plano/01](plano/01-monorepo-descoberta.md).

**MCP adiado.** O agente chama a CLI pelo terminal com `--json`, o que funciona nas três ferramentas sem registrar
servidor. `figma2dart mcp` volta se algum ambiente não tiver terminal. Primeira validação: Copilot no VS Code com o
Luna 5.6; opencode e Claude Code depois (o `init` ganha o formato de agente de cada um).

**Entrada principal: o `.zip` do plugin do Figma.** Pelo MCP do Figma, o agente gasta ~8 mil tokens por chamada
enviando o extrator, e depende de quem tem acesso ao MCP. O plugin não tem custo de tokens e funciona para qualquer
pessoa.

### 10.10 Modelo-alvo

A LLM padrão da empresa é o **Luna 5.6**. As características dele (contexto, raciocínio em várias etapas) não foram
avaliadas aqui, então o desenho não depende delas: contexto pequeno por tarefa, um arquivo de entrada, norte na linha
que precisa mudar, regras curtas com exemplo e um critério de pronto que um comando verifica. Antes de fixar o
tamanho do brief, avaliar com **3 a 5 telas reais** de complexidades diferentes e critérios fixos (compila, scaffold
certo, sem valor solto, fiel ao PNG, quantidade de `f2d:inferred`).

---

## 11. Snapshot `figma_specs/`

Gerado pelo exportador (plugin ou CI via MCP) e commitado no repositório do DS:

```
figma_specs/
  library.ir.json            ← tokens, text styles, componentes, variants
  naming.yaml                ← exceções de nome (tokens, ícones)
  components/
    button.md                ← "Inspect sem Dev Mode": props, variants, layout com tokens, imagens
    button/variant=primary,size=md,state=default.png
    …
```

- O **diff do PR** do snapshot mostra o que mudou no Figma ("Button ganhou `size=lg`").
- O `.md` substitui o Dev Mode para quem constrói ou mapeia componentes.
- Um componente novo pode ser rascunhado por LLM a partir do `.json` + PNGs, já com os nomes dos tokens; um dev revisa.

---

## 12. Regras para o arquivo de design (lint)

O plugin verifica e lista as violações, porque cada uma degrada a geração:

| Regra | Por quê |
|---|---|
| Não renomear camadas de instância | No MCP nativo, `data-name` é o único identificador do componente achatado |
| Toda variável com code syntax WEB (`var(--…)`) | Sem ele, o MCP nativo devolve `12px` em vez de `var(--spacing-md)`. O extrator não depende disso |
| Sem valores soltos (cor hex sem variável nem estilo, espaçamento fixo, texto sem estilo) | Viram nós sem `token` |
| Nomes únicos entre bibliotecas | Nome repetido ganha sufixo de key e fica difícil de mapear |
| Sem instâncias detached | A tela perde o vínculo com o componente |
| Componentes de construção com prefixo `_` ou `.` (ex.: `.Nested / Global Switcher`) | Não são publicados nem listados como componentes do DS. Se têm widget próprio, ganham um `.figma.dart` pela key como qualquer outro; se não, o mapeamento do componente pai lê as props deles com `nested(path)` |

---

## 13. Pontos em aberto

- **Rate limits da REST por seat:** confirmar os números atuais na documentação da Figma antes de depender da REST.
- **Distribuição do plugin:** plugin privado da organização exige plano Organization/Enterprise. No Pro, cada
  pessoa importa o `manifest.json` como development plugin.
- **Quem roda o plugin:** confirmar se seats de visualização conseguem executar o export no plano da empresa.
- **MCP oficial por seat:** confirmar quais seats acessam o MCP. O pipeline não depende disso, mas afeta quem usa o caminho MCP.
- **`AcmeContext`:** confirmar se a configuração muda por tela e quem decide. Define se vai no `@FigmaScreen`, nos
  `devNotes` dos templates ou vira pergunta no brief (10.2).
- **Templates desanexados:** medir quão comum é no time de design. Se for comum, os docs dos templates precisam ser
  mais completos, talvez com uma tela inteira de exemplo (7.6).
- **Dono da anotação e do doc:** recomendação: o time do DS, no mesmo PR, porque a validação de cobertura cobra os dois.
- **Luna 5.6:** avaliação com telas reais antes de fixar o formato do brief (10.10).
- **Construção de componentes fora do DS (feature futura).** Hoje vira placeholder (10.5). A feature terá:
  - **Escolha do usuário:** para cada placeholder, criar o componente, manter o placeholder ou usar um componente
    do DS indicado por ele.
  - **Tarefa própria** (`f2d:build`) com brief de construção. **O brief já existe** (10.6, `components/<nome>/`);
    faltam a escolha do usuário, o marcador `f2d:build`, tokens traduzidos para Dart, assets e exemplo.
  - **Esqueleto gerado:** classe, construtor tirado das props do Figma e `build` tirado da árvore.
  - **Reuso:** componente construído ganha um `*.figma.dart` no app, pela key dele; a próxima tela sai
    determinística, e a CLI avisa sobre duplicatas.
  - **Política de componentes locais** no `FigmaPolicy` (pasta, nome, só tokens, compor com o DS) e exemplo de
    referência no `carteira_ds_examples`.
  - **Ordem:** componentes a construir antes da tela.

  **Restrições para não bloquear a feature** (valem para toda decisão a partir de agora):
  1. O IR continua exportando componentes locais em profundidade e a árvore completa do que está fora do DS. Não
     cortar isso para economizar tamanho.
  2. O placeholder carrega o id do nó, a key (quando é instância), o nome e o tipo, para a feature achar e
     substituir exatamente aquele ponto.
  3. O placeholder mantém o tamanho do Figma, para a substituição não exigir mexer no layout em volta.
  4. A exportação de assets (preenchimentos de imagem e vetores, que hoje o IR não traz como arquivo) continua
     prevista no roadmap.
  5. A busca de mapeamento é por key e não depende do pacote do DS: um `*.figma.dart` precisa funcionar também
     dentro de um app.
  6. A classificação "do DS × fora do DS" fica num único lugar do gerador, onde a feature vai se ligar.
  7. `brief` e `check` tratam tipos de tarefa de forma extensível, para receber a tarefa de construção e a escolha do
     usuário (pela skill ou por uma ferramenta do MCP).

---

## 14. Roadmap

1. ✅ **Plugin + extrator** (`figma_plugin/`): tipos do IR v1, schema gerado, extrator com os quatro `kind`, lint,
   UI de export e bundle para o `use_figma` com paginação.
2. ✅ Extrator rodado via MCP nos casos reais do POC (v0.2 revisado para DS maiores, seção 5.8); fixtures em `figma_plugin/examples/` (component set
   `TransactionItem` e fluxo de 5 telas), validados contra o schema. Plugin rodado no Figma desktop: IR igual ao do MCP, exceto `source.via`,
   `fileKey` (ausente em plugin de desenvolvimento) e imagens.
3. `figma_connect` com a API completa (incluindo `coverage`, `guide`, `figmaNotes`, `guided`, `slot`, `devNotes`)
   e `carteira_ds_figma` com os 10 mapeamentos do POC, ao menos um parcial para exercitar o norte.
4. `figma2dart generate`, `brief` e `check` para as 5 telas + golden tests contra os PNGs. Fase 1 ✅: `figma2dart resolve`
   (`figma2dart/`) resolve cada instância em código Dart pelos mapeamentos e escreve `BRIEF.md` + `resolved.json`.
5. `figma2dart mcp`, skill `figma-to-flutter`, plugin do Copilot e `figma2dart init`.
6. Piloto no DS real: 3 a 5 telas com o Luna 5.6 e critérios fixos; ajustar anotações, docs e regras.
7. `drift`, validação de cobertura e `docs status` na CI.
8. Importer MCP nativo (opcional: o `.zip` do plugin é a entrada principal).

---

## Referências do POC

| Item | Onde |
|---|---|
| Arquivo Figma do DS | https://www.figma.com/design/sgwwQGDTn2rhRA1PMaqL5f (Carteira DS) |
| Arquivo Figma do fluxo | https://www.figma.com/design/1meYjTskBd3JSKuHxeQ9A2 (Fluxo de Transferência) |
| Especificação do DS | [DS_PLAN.md](../DS_PLAN.md) |
| DS em Flutter | `/Users/pablostefan/GitHub/design_system/carteira_design_system` |
