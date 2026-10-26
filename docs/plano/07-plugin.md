# 07 · Plugin: conteúdo das instâncias e texto

**Status: feita** (inclusive o recorte do PNG por instância), validada com exports reais do plugin novo
([AUDITORIA.md](../AUDITORIA.md#validação-dos-exports-reais-07)). Falta só sketch do DS e `maxLines` num export real.

## Problema

- Instância é serializada rasa ([serialize.ts:74](../../figma_plugin/src/extractor/serialize.ts#L74)): só props,
  expostas e overrides. Para montar um sketch como o Extrato, o que importa é o que está dentro (dias, linhas,
  valores), e isso não vem.
- Texto não traz `maxLines`, reticências nem como cresce (`textAutoResize`).
- Para sketch só há o PNG da tela inteira, sem recorte da instância.

## Proposta

- **`instance.content`:** lista compacta dos textos visíveis e das instâncias dentro de cada instância (caminho,
  texto ou componente + props). Serve ao sketch, ao `gap` e ao `f2d:guided`.
- **Texto:** `maxLines`, `textTruncation`, `textAutoResize`.
- **Opcional:** posição de cada instância relativa à tela, para a CLI recortar o PNG por instância (pede a
  dependência `image` na CLI).
- Subir a versão do IR; a CLI aceita a anterior.

## Tarefas

- [x] `serialize.ts`: `content` e campos de texto; tipos em `ir.ts`; schema.
- [x] CLI: `content` no brief de montagem; `maxLines`/reticências na estrutura.
- [x] (opcional) posição + recorte.

## Verificação

Testes do plugin; export real de uma tela com o Extrato (depende de publicar o DS no Figma).

## Decisões em aberto

- ~~Recorte do PNG por instância?~~ Sim, com a dependência `image` na CLI.
- ~~Limite do `content` em telas grandes~~ 200 itens por instância, com `contentTruncated` (o brief avisa).

## Resultado

- **Plugin (extrator 0.4, IR 1.3.0):** instância numa tela grava `bounds` (caixa relativa ao frame) e
  `instance.content` (textos e instâncias visíveis de dentro, com caminho e props; até 200 itens, `contentTruncated`
  depois); o estado da tela grava `imageScale` (2, a mesma constante do export do PNG); texto grava `maxLines`,
  `truncation: 'ENDING'` e `autoResize` fora do padrão. Instâncias em definição de componente não ganham caixa nem
  conteúdo (não estão numa tela).
- **CLI:** aceita IR 1.3; o brief de montagem (`sketch`/`local`) mostra o conteúdo de dentro e o recorte do PNG da
  tela só daquela instância (`components/<nome>/<id>.png`, recortado com a biblioteca `image` pela caixa × escala); a
  estrutura mostra "máx N linhas", "reticências" e "quebra linha (largura fixa)"/"caixa fixa"/"corta na caixa".
- Export antigo (IR 1.2) continua igual: sem recorte nem conteúdo.

## Prova

- Plugin: `npm run check` (tipos, testes, build, schema e exemplos): caixa relativa ao frame, conteúdo na ordem das
  camadas (sem os ocultos), nada disso dentro de definição de componente, limites de texto.
- CLI: 72 testes; `crop_test` monta um zip com o PNG da tela (2x) e um sketch com caixa e conteúdo: o recorte sai com
  60×80 px e só o pedaço pintado, o brief traz o recorte e o conteúdo; IR 1.2 sem recorte.
- As 5 telas do export real (IR 1.2) resolvem como antes.

## Falta

- Uma tela com o `Template / Extrato` (sketch) e um texto com limite de linhas, num export real.
- `Color.fromRGBO`/`Offset` e afins no `check`, e dicas de recorte para instâncias `gap` (hoje só sketch/local).
