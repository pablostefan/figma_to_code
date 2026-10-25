# 08 · Comparação visual por golden (depois)

## Problema

Nada pega erro visual: espaçamento errado, cor trocada, ordem de elementos. Teste de widget só confere textos.

## Proposta

Um teste de golden renderiza o widget construído (ou a tela) em PNG; a LLM abre esse PNG e o da variante do Figma
e corrige as diferenças. É o único passo que pega erro visual.

## Riscos

- Fontes: sem carregar as fontes do Acme no teste, o texto sai como caixas e a comparação perde valor.
- Diferença de renderização entre máquinas; o golden aqui é para a LLM olhar, não para travar CI.

## Decisões em aberto

- Agora ou depois das questões 01–07?
