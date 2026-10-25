# 07 · Plugin: conteúdo das instâncias e texto

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

- [ ] `serialize.ts`: `content` e campos de texto; tipos em `ir.ts`; schema.
- [ ] CLI: `content` no brief de montagem; `maxLines`/reticências na estrutura.
- [ ] (opcional) posição + recorte.

## Verificação

Testes do plugin; export real de uma tela com o Extrato (depende de publicar o DS no Figma).

## Decisões em aberto

- Recorte do PNG por instância (dependência `image`)?
- Limite de tamanho do `content` por instância em telas grandes.
