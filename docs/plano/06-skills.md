# 06 · Skills de construir e de montar

## Problema

- A montagem de sketch é um parágrafo dentro da skill de tela, junto com todo o resto.
- A skill de construir manda escrever direto, sem antes ligar cada camada a um widget/token.
- Nada escreve a anotação do app no fim (ver [02](02-acme-e-componentes-do-app.md)).

## Proposta

- **`figma2dart-component` (construir):** 1) tabela camada → widget/token antes de escrever; 2) widget; 3) teste por
  variante; 4) `check`; 5) `@FigmaLocal`.
- **`figma2dart-assemble` (montar), nova:** serve o sketch do Acme e o `local` do app (mesmo fluxo). Por
  instância: tabela dado do Figma → parâmetro da API, depois o código; `f2d:inferred` no que decidiu sem base.
  A skill de tela chama esta para cada `sketch`/`local`.
- **Agente:** etapa "escolher o app" ([01](01-monorepo-descoberta.md)); pergunta sobre `existing`
  ([02](02-acme-e-componentes-do-app.md)).

## Tarefas

- [ ] Reescrever `figma2dart-component`.
- [ ] Criar `figma2dart-assemble`; enxugar a parte de sketch da `figma2dart-screen`.
- [ ] Agente orquestrador e subagente com os passos novos.
- [ ] `init` instala a skill nova.

## Verificação

Rodar o agente no Copilot com o fluxo do Carteira: um componente construído, um `existing` reaproveitado, um
sketch montado; `check` ok no fim.

## Decisões em aberto

- Montagem como skill chamada pela de tela (recomendado) ou subagente separado?
