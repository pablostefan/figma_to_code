# 03 · Brief completo com o que o IR já tem

**Status: feita.** Resultado e prova no fim do arquivo.

## Problema

O plugin já exporta muito mais do que os briefs mostram. A
[structure.dart](../../figma2dart/lib/src/structure.dart) e o
[component_brief.dart](../../figma2dart/lib/src/component_brief.dart) deixam de fora:

| No IR | Hoje no brief | Efeito |
|---|---|---|
| `exposed` nos usos de um componente a construir | não aparece ([component_brief.dart:98](../../figma2dart/lib/src/component_brief.dart#L98)) | **Erro:** `DsAvatar.initials('AS')` fixo, todo contato sai "AS" |
| `size` / `sizeTokens` de nó `FIXED` | só `FIXED×HUG` | divisor de 1px, ícone de 20px viram chute |
| `padding` | `Spacing/md/0/Spacing/md/0` sem rótulo | ordem ambígua (cima/dir/baixo/esq) |
| `gap: 'auto'` | `gap auto` | não diz que é "espaço entre" |
| `effects`, `opacity`, `clipsContent` | não aparece | sombra e opacidade somem |
| `position`, `limits` | não aparece | sobreposição e largura máxima somem |
| texto `align`, `segments`, `font` | não aparece | alinhamento e estilos mistos somem |
| override de instância | JSON cru | ruído |
| `svg` de componente só de vetor | vira `TODO(f2d)` | asset existe e não é usado |
| N variantes | N árvores inteiras | a LLM precisa achar sozinha o que muda |

## Proposta

- **Expostas:** em "Usos", os valores das instâncias expostas de cada uso; na estrutura, "exposta: vem do uso";
  na API proposta, um parâmetro por prop exposta que muda entre os usos (`initials`).
- **Estrutura:** tamanho de `FIXED` (com token quando houver); `padding T … · R … · B … · L …`; `auto` como
  "espaço entre"; sombra, opacidade, clip, posição absoluta, min/max; alinhamento e trechos do texto; override
  legível (`cor Color/text/secondary`).
- **Tabela de variação:** linhas = camada · atributo, colunas = valor de cada variante. Uma árvore base e só as
  diferenças, em vez de N árvores.
- **SVG:** gravar o `svg` do componente só de vetor na pasta da tarefa; o `TODO(f2d)` aponta para o arquivo.

## Tarefas

- [x] `component_brief.dart`: expostas em Usos e na API proposta.
- [x] `structure.dart`: tamanho, padding rotulado, espaço entre, efeitos, posição, limites, texto, override.
- [x] Tabela de variação (base + diferenças).
- [x] SVG na pasta da tarefa.
- [x] Atualizar os testes que comparam o texto da estrutura.

## Verificação

- Fixture do fluxo: brief do `ContactItem` com `initials` na API e `AS`/`BL`/`CD` nos usos.
- Teste sintético de componente com 3 variantes: a tabela mostra só o que muda.
- Prova real: uma LLM constrói o `ContactItem` só com o brief, antes e depois.

## Resultado

- `structure.dart` reescrito: gera linhas com caminho (para comparar variantes) e mostra tamanho (`L×A`, número ou
  token no eixo fixo; a raiz do componente sem número), limites, padding por lado, "espaço entre", wrap/grade,
  sombra/desfoque, opacidade, clip, borda e raio por lado (só os não zerados), posição absoluta, gradiente,
  estilos de cor, alinhamento/fonte/trechos de texto, override legível, **tamanho de toda instância** e a marca
  **exposta**.
- Brief de construção: parâmetro por prop exposta que muda entre os usos (tipo pelo valor: `bool`, enum de ícone,
  `String`); usos com as expostas; uma árvore (a base) e "O que muda em cada variante"; SVG gravado na pasta;
  regra do tamanho de instância.
- Brief da tela: legenda da estrutura; placeholder com as expostas.

## Prova

- 62 testes; `structure_test.dart` (3 variantes, sombra, trechos, posição, limites, SVG) e o `ContactItem` real
  (`avatarInitials` com AS/BL/CD, expostas nos usos, override legível, 20×20 do chevron).
- **Construção só com o brief:** o `ContactItem` saiu certo de primeira (compila, teste dos 3 usos passa, `check`
  ok com 1 `f2d:inferred` no `onTap`). Comparado com o feito à mão, a única diferença era o chevron: o Figma tem
  20×20, o mapeamento do Icon não lê tamanho e o brief não mostrava — corrigido (tamanho de instância na linha).

## O que ainda depende de outras questões

- Achar a constante Dart de cada token (`Spacing/2xs` → `DsSpacing.xxs`) ainda é busca: [04](04-tokens-em-dart.md).
- Parâmetro de widget do DS que o override pede (`color:` do `DsIcon`) a LLM acha lendo o widget; o mapeamento do
  Icon também deveria ler o tamanho (ajuste no `carteira_ds_figma`, não na CLI).
- Quebra e reticências de texto (`maxLines`) não vêm no IR: [07](07-plugin.md).
